# Sample Integration of Mobb in Atlassian Bamboo
This is a sample integration that demonstrates the use of Mobb CLI (Bugsy) in a CI/CD environment. The scenario demonstrates a developer performing a pull request on a GitHub repository, which triggers a Bamboo build pipeline. During the pipeline job, a SAST scan will run to detect for possible vulnerabilities, followed by an analysis by Mobb on the scan result to produce possible autofixes. 

# Usage

## Register

To perform this integration, you will need the following:

* Sign up for a free account at https://mobb.ai
* Sign up for a free Snyk Account https://snyk.io 
* Access to a Atlassian Bamboo environment
* Access to a GitHub repository to perform this integration

## (Optional) GitHub Personal Access Token (PAT)

This step is required if you want to publish the Bamboo build progress as well as the dedicated Mobb Fix LInk back into the GitHub Pull Request page. To generate a GitHub Personal Access Token (PAT)click on your GitHub profile icon -> Settings -> Developer Settings -> Personal Access Tokens -> Fine-grained tokens. 

For this integration, we need to provide the following permissions: 

* Commit Statuses - Read and Write
* Contents - Read and Write
* Pull Requests - Read and Write
* Access to the repository where this integration will be performed

Note down the generated GitHub PAT and store it in a safe place. 

## Generate Mobb API Key and Snyk API Key

After logging into the Mobb portal, click on the "Settings" icon on the bottom left, then select "Access tokens". From here, you can generate an API key by selecting the "Add API Key" button.

To integrate with Snyk, you  will also need to generate a Snyk API Key. This can be achieved by following this [guide](https://docs.snyk.io/snyk-api/authentication-for-api) from Snyk documentation. 

## Loading Credentials into the Bamboo Project

At this point, we should have 3 API keys ready: 
* GitHub Personal Access Token (PAT)
* Mobb API Key
* Snyk API Key

The next step is to load them into Bamboo. To do so, go to your Bamboo  project, under "Bamboo Administration", go to "Global Variables". The variable names we are using in this example are as follows:

![image](https://github.com/antonychiu2/mobb-bamboo-integration/assets/5158535/57722810-4660-4ecf-a820-083c16c8ab1e)

```
GITHUB_PAT_SECRET
MOBB_API_SECRET
SNYK_API_SECRET
```


## Bamboo Specs (.yml)

In this demo, we are checking in the build script into the source code repository under the path `./bamboo-specs/build/plan.yml`. Here is a sample `yaml` script for your reference:

``` yaml
version: 2
plan:
  project-key: MOB
  key: MOB
  name: Mobb-Demo-Plan
stages:
- Default Stage:
    manual: false
    final: false
    jobs:
    - SAST-Mobb-Autofixer
SAST-Mobb-Autofixer:
  key: JOB1
  description: Run SAST Scan, if issues are found, run Mobb Autofixer to auto fix all issues.
  tasks:
  - checkout:
      force-clean-build: false
      description: Checkout Default Repository
  - script:
      interpreter: SHELL
      scripts:
      - |-
        chmod +x ./bamboo-specs/update_github_status.sh
        ./bamboo-specs/update_github_status.sh $bamboo_GITHUB_PAT_SECRET $bamboo_planRepository_username $bamboo_planRepository_name $bamboo_planRepository_revision "pending" $bamboo_buildResultsUrl "Bamboo job has started" "continuous-integration/bamboo"
      description: Notify Github on the start of the job
  - script:
      interpreter: BINSH_OR_CMDEXE
      scripts:
      - |-
        # Update GitHub to indicate SAST Scan is starting
        ./bamboo-specs/update_github_status.sh $bamboo_GITHUB_PAT_SECRET $bamboo_planRepository_username $bamboo_planRepository_name $bamboo_planRepository_revision "pending" $bamboo_buildResultsUrl "Snyk Scan Started" "continuous-integration/bamboo/snyk"

        npx snyk auth $bamboo_SNYK_API_SECRET
        issues_found=false
        npx snyk code test --sarif-file-output=report.json
        exit_code=$?

        # Update GitHub PR on whether vulns are found
        if [ $exit_code -eq 0 ]; then
            echo "(Success) Snyk completed with exit code $exit_code."
            ./bamboo-specs/update_github_status.sh $bamboo_GITHUB_PAT_SECRET $bamboo_planRepository_username $bamboo_planRepository_name $bamboo_planRepository_revision "success" $bamboo_buildResultsUrl "Snyk Scan Complete - No issues found!" "continuous-integration/bamboo/snyk"
        else
            echo "(Failure) Snyk completed with exit code $exit_code."
            ./bamboo-specs/update_github_status.sh $bamboo_GITHUB_PAT_SECRET $bamboo_planRepository_username $bamboo_planRepository_name $bamboo_planRepository_revision "failure" $bamboo_buildResultsUrl "Snyk Scan Failed - Vulnerabilities found!" "continuous-integration/bamboo/snyk"
            issues_found=true
        fi
        echo "Issue found: $issues_found"
        echo "issues_found=$issues_found" >> status.properties
        exit $exit_code
      description: SAST scan
  final-tasks:
  - inject-variables:
      file: status.properties
      scope: RESULT
      namespace: inject
      description: Load SAST scan status
  - script:
      interpreter: SHELL
      scripts:
      - |
        # Extract GitHub URL to be used by bugsy
        GITHUBURL=$(echo $bamboo_repository_git_repositoryUrl | sed -E 's|(https://github.com/[^/]+/[^/]+).git|\1|') 
        echo "Github URL is: $GITHUBURL"
        # Mobb CLI
        MOBBURL=$(npx mobbdev@latest analyze -f report.json -r $GITHUBURL --ref $bamboo_planRepository_branchName --api-key $bamboo_MOBB_API_SECRET --ci)
        echo "Mobb URL: $MOBBURL"
        # Publish the Mobb Fix Link back to GitHub
        ./bamboo-specs/update_github_status.sh $bamboo_GITHUB_PAT_SECRET $bamboo_planRepository_username $bamboo_planRepository_name $bamboo_planRepository_revision "success" $MOBBURL "Click on \\\"Details\\\" to access the Mobb Fix Link" "Mobb Fix Link"
      conditions:
      - variable:
          equals:
            # Only run this step if issues were found during the previous SAST step
            bamboo.inject.issues_found: 'true'
      description: Mobb
  - script:
      interpreter: SHELL
      # Notify GitHub PR that the pipeline is complete
      scripts:
      - ./bamboo-specs/update_github_status.sh $bamboo_GITHUB_PAT_SECRET $bamboo_planRepository_username $bamboo_planRepository_name $bamboo_planRepository_revision "success" $bamboo_buildResultsUrl "Bamboo job is complete" "continuous-integration/bamboo"
      description: Notify GitHub on the end of the job
  artifact-subscriptions: []
repositories:
- mobb-bamboo-integration:
    scope: global
triggers:
- remote:
    description: remote-trigger
branches:
  create:
    for-pull-request:
      accept-fork: true
  delete:
    after-deleted-days: 7
    after-inactive-days: 30
  link-to-jira: false
notifications: []
labels: []
dependencies:
  require-all-stages-passing: false
  enabled-for-branches: true
  block-strategy: none
  plans: []
other:
  concurrent-build-plugin: system-default

```
This is referenced by `bamboo-specs/bamboo.yml` which contains the following:

```yaml
!include 'build/plan.yml'
```


## Triggering the pipeline

The Bamboo build pipeline will run when a new commit is detected in the GitHub Source Code repository that it is connected with. To test this, go to your GitHub Repository and trigger a Pull Request by making an update to your source code in a new branch. 

<img src="https://github.com/antonychiu2/jenkins-mobb-integration/assets/5158535/171bad00-c5c0-4bb1-89c5-fc291e63d3b8" width=70% height=70%>

Once the Pull Request is initiated, the build pipeline in Bamboo will initiate. 

If vulnerabilities are found by the SAST scanner, Mobb will also run to consume the results of the SAST scan. Once the analysis is ready, a URL to the Mobb dashboard will be provided via the "Details" button. 

<img src="https://github.com/antonychiu2/mobb-bamboo-integration/assets/5158535/c40f2e9e-114d-4389-93b1-221fd31c9646" width=70% height=70%>

Once we arrive at the analysis page for the project, we can see a list of available fixes. Let's click on the "Link to Fix" button next to the SQLi finding.

<img src="https://github.com/antonychiu2/mobb-bamboo-integration/assets/5158535/1edbe5a1-db64-4365-9c05-f378ad010d56" width=90% height=90%>

Mobb provides a powerful self-guided remediation engine. As a developer, all you have to do is answer a few questions and validate the fix that Mobb is proposing. From there, Mobb will take over the remediation process and commit the code on your behalf.

Once you're ready, select the "Commit Changes" button.

<img src="https://github.com/antonychiu2/mobb-bamboo-integration/assets/5158535/fe93e5be-88e4-49e8-a3f3-143d9faaac7f" width=90% height=90%>

As the last step, enter the name of the target branch where this pull request will be merged, then select "Commit Changes".

<img src="https://github.com/antonychiu2/jenkins-mobb-integration/assets/5158535/03544f61-681c-4b21-8566-fcd4739afa06" width=70% height=70%>

Mobb has successfully committed the remediated code back to your repository under a new branch along with a new Pull Request. Since this pipeline is configured to run on every Pull Request events, a new SAST scan will be conducted to validate the proposed changes to ensure the vulnerabilities have been remediated.

<img src="https://github.com/antonychiu2/mobb-bamboo-integration/assets/5158535/47250fc6-09c7-4317-a7f3-1a2c56eab758" width=70% height=70%>




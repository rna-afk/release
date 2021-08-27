# e2e tests steps generator for new Cloud Plarforms

## Description

This is the document to explain the [steps generator code](installer-new-cloud-steps-creator.sh).
The generator creates the required IPI and UPI steps needed for a new cloud platform CI testing.

## Prerequisites
There is no special prerequisites to run the script. Basic bash functions are enough.

## Flowchart
- The code first takes in one input which is the cloud platform name. The input is used to create folders
so a shortened version of the name is recommended.

- A new e2e test configuration is appended to the openshift-installer-master file to create a workflow for 
the e2e test.

- The container information is then appended to the openshift-installer-master-presubmits file which specifies
secrets, trigger etc.

- IPI and UPI directories are created with the cloud name provided along with the OWNERS and metadata files that will
be reused everywhere required.

- The IPI and UPI pre and post chain steps are created with the yaml files needed.

- A new folder is created in the conf folder to create the OWNERS, metadata, yaml and a placeholder bash file
for the user to fill in. The file must contain the configuration commands needed to create an install config
for IPI and UPI installation. This will be common for both IPI and UPI. Be sure to check the yaml workflow file
to change the environment variables required.

- An openshift-e2e-{CLOUD_PLATFORM} is created to link the pre and post steps. This is mainly used by CI to run 
the test in order.

- The UPI install step is created next with a placeholder bash file that needs to be filled. This file will be run to create an
UPI installation in the cloud platform. It already has a few important commands that needs to be run.

- The release repo has a few checks to run and hence, sudo make all is run to clean the job a little.

## Improvements

- Code needs to have option to just create either IPI or UPI to provide more flexibility.

- Need another script to create boskos leases and add the quotas to the CI.
# cloudify_deployment
Scripts to deploy dockerized version of the Cloudify manager from the project github repos - https://github.com/cloudify-cosmo

Despite official docker image available for download at the Cloudify website these scripts are light and downloads all dependencies on flight. Additionall functionality supported is:
1. Choose which components has to be installed, f.e. skip monitoring components deployment which is supported starting from the Cloudify 4.4.0. For this, config.yaml.template file should be modified.
2. Choose upstream branch to be used for the platform deployment. This can be achieved by setting variable CFY_MANAGER_INSTALL_BRANCH, which used as a pointer to the apprpriate branch at the official Cloudify github. These scripts were tested to deploy Cloudify 4.3.x and 4.4.x.

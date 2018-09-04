#!/bin/bash

CFY_MANAGER_INSTALL_REPO="https://github.com/cloudify-cosmo/cloudify-manager-install.git"
CFY_MANAGER_ROOT="/opt/cloudify"
CFY_MANAGER_INSTALL_BRANCH="4.4.1-build"
MANAGER_CONFIG_LOCATION="/etc/cloudify"
MANAGER_SOURCES_URL="https://github.com/cloudify-cosmo/cloudify-versions"
CFY_BASE_IMAGE="common"

CFY_MANAGER_INSTALL_FOLDER="${CFY_MANAGER_ROOT}/cloudify-manager-install"
CFY_CONTAINER_NAME="cfy-manager-${CFY_MANAGER_INSTALL_BRANCH}"
MANAGER_SOURCES_DIR="${CFY_MANAGER_ROOT}/sources"
DOCKER_RUN_FLAGS="--name ${CFY_CONTAINER_NAME} -d -v /sys/fs/cgroup:/sys/fs/cgroup:ro --tmpfs /run
 --tmpfs /run/lock --security-opt seccomp:unconfined --cap-add SYS_ADMIN"

# Unless image exists, we should build it
docker images ${CFY_BASE_IMAGE} > /dev/null
if (($? != 0 )) ;
then
  echo "Building common Docker images with Centos7/SystemD"
  docker build -f ./Dockerfile-common -t ${CFY_BASE_IMAGE} .
fi

# If cloudify container already exists we should stop further steps and exit
docker ps -a | grep ${CFY_CONTAINER_NAME}
if (($? == 0 )) ;
then
  echo "Container ${CFY_CONTAINER_NAME} already exists. Stopping build..."
  exit 1
fi


echo "Creating empty container using common image..."
docker run ${DOCKER_RUN_FLAGS} ${CFY_BASE_IMAGE}
CONTAINER_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CFY_CONTAINER_NAME})

# Enabling sshd server internally, required for sanity checks
docker exec -d $CFY_CONTAINER_NAME bash -c "systemctl enable sshd.service && systemctl start sshd.service"

#
echo "Cloning cfy installer sources and building installer..."
docker exec -t $CFY_CONTAINER_NAME bash -c "mkdir -p ${CFY_MANAGER_ROOT}"
# sed is required due to inconsistency among variable names used in 4.3.2 branch. 
docker exec -t $CFY_CONTAINER_NAME bash -c "cd ${CFY_MANAGER_ROOT} && git clone $CFY_MANAGER_INSTALL_REPO -b $CFY_MANAGER_INSTALL_BRANCH \
			&& sed -i 's/GATEKEEPER_BUCKET_SIZE/AGENT_MAX_WORKERS/' $CFY_MANAGER_INSTALL_FOLDER/cfy_manager/components/mgmtworker/config/cloudify-mgmtworker"

# Dirty hack to install dependencies requires in setup.py file
# Basically generating requirements.txt from the argument specified for setup()
# Additionally we should upgrade setuptools
docker exec -t $CFY_CONTAINER_NAME bash -c "cd $CFY_MANAGER_INSTALL_FOLDER \
					    && sed -e '/install_requires=/,/\]/!d' setup.py | grep -v \"\[\|\]\" | tr -d \'\, > requirements.txt \
					    && pip install pip==7.1.0 \
					    && pip install -r requirements.txt \
					    && pip install --upgrade setuptools \
					    && python setup.py install"

# Assuming config.yaml will be preprovided as a template. So IPs should be modified only. \x27 is the hex of the single quote
cp config.yaml.template config.yaml
sed -i "s/private_ip: \x27\x27/private_ip: ${CONTAINER_IP}/g" config.yaml
sed -i "s/public_ip: \x27\x27/public_ip: ${CONTAINER_IP}/g" config.yaml
#echo "Creating install config file..."
#echo "manager:
#  private_ip: ${CONTAINER_IP}
#  public_ip: ${CONTAINER_IP}
#  set_manager_ip_on_boot: true
#  security:
#    admin_password: admin" > config.yaml

docker exec -t $CFY_CONTAINER_NAME bash -c "mkdir ${MANAGER_CONFIG_LOCATION}"
docker cp config.yaml ${CFY_CONTAINER_NAME}:${MANAGER_CONFIG_LOCATION}
docker exec -t $CFY_CONTAINER_NAME bash -c "mkdir -p ${MANAGER_SOURCES_DIR}"

# Getting URLs and downloading rpm packages for a given manager version
#
docker exec -t $CFY_CONTAINER_NAME bash -c "git clone  -b ${CFY_MANAGER_INSTALL_BRANCH} ${MANAGER_SOURCES_URL} ${MANAGER_SOURCES_DIR}"
#Assuming packges URLs are specified at the ${MANAGER_SOURCES_DIR}/packages-urls/manager-packages.yaml file. Downloading them
docker exec -t $CFY_CONTAINER_NAME bash -c "cd  ${MANAGER_SOURCES_DIR} && while read -r URL ; do echo \$URL && curl \$URL -o \${URL##*/} ;\
					     done < ${MANAGER_SOURCES_DIR}/packages-urls/manager-packages.yaml"


echo "Installing manager..."
docker exec -t ${CFY_CONTAINER_NAME} bash -c "cfy_manager install"
#docker exec -t ${CFY_CONTAINER_NAME} bash -c "echo 'docker' > /opt/cfy/image.info"

**netop-tools** provides a set of **Network-Operator** configuration
automation scripts.

**netop-tools** simplifies the configuration of common Network-Operator
use cases.

**git clone <https://github.com/Mellanox/netop-tools.git>**

**cd ./netop-tools**

**git checkout master**

**source "NETOP\_ROOT\_DIR.sh"** \# create the NETOP\_ROOT\_DIR env
variable.

The **global\_ops.cfg** file defines the shared global configuration
values for Network-Operator.

Edit the **global\_ops.cfg** setting K8s networking parameters and
selecting the USECASE.

**./setuc.sh** \# set the uc symlink for the selected USECASE

**cd ./uc** \# edit the netop.cfg for the use case specific
configuration

**cd \${NETOP\_ROOT\_DIR}**

**./ins-k8.sh** \# installs os specific K8s Network-Operator

\# and dependencies on a bare metal control plane.

**kubectl get pods --A** \# verify that the Network-Operator pods are
ready

\# for applying the network configuration

**cd ./uc**

**${NETOP_ROOT_DIR}/ops/apply-network-cr.sh** \# use global\_ops.cfg (includes
{USECASE}/netop.cfg)

\# to apply the use case specific network resources

**${NETOP_ROOT_DIR}/ops/mk-app.sh test** \# make the sample app

**${NETOP_ROOT_DIR}/ops/run-app.sh test** \# run the created pod test app

\# use kubectl get pods --A to check the pod status

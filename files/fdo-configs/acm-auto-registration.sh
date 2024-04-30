#!/bin/bash

####### k8s clients
#######
curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -xvf openshift-client-linux.tar.gz
chmod +x oc 
cp oc /usr/bin/
chmod +x kubectl 
cp kubectl /usr/bin/

mkdir ~/.kube
cp /var/lib/microshift/resources/kubeadmin/kubeconfig ~/.kube/config

##### Variables
ACCESS_TOKEN=<YOUR_ACM_TOKEN>
HOST=<YOUR_ACM_HOST>

# copy pull secret
cp /var/home/admin/pull-secret.json /etc/crio/openshift-pull-secret
chmod 600 /etc/crio/openshift-pull-secret


# register MicroShift cluster to ACM hub
curl -k -H "Authorization: Bearer $ACCESS_TOKEN" https://$HOST/agent-registration/crds/v1 | oc --kubeconfig /var/lib/microshift/resources/kubeadmin/kubeconfig apply -f -
curl -k -H "Authorization: Bearer $ACCESS_TOKEN" https://$HOST/agent-registration/manifests/microshift-$(tr -dc a-z0-9 </dev/urandom | head -c 5 ; echo '') | oc --kubeconfig /var/lib/microshift/resources/kubeadmin/kubeconfig apply -f -

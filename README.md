# DAY 1

The first step to install an edge device in a remote and unmanned location is automating the onboarding of the device in a secure way.

## DAY 1 - Device Onboarding

The advantages of having a standardize onboarding process are:
- Simplicity: having a highly automated process effectively brings ‘plug and play’ to the world of onboarding edge nodes and IoT devices.  

- Flexibility: businesses can choose which cloud or edge platforms they want to onboard devices to at the point of installation (as opposed to when devices are manufactured) in a *Late Binding* fashion.   

- Security: leveraging a ‘zero trust’ approach, which means the installer no longer needs – nor has access to – any sensitive infrastructure/access control information.  

For this purpose FIDO Device Onboarding (FDO) was introduced.

This is how FDO works:  
<img align="center" src="./assets/FDO-Onboarding-image-1024x576.jpg?raw=true">  

We will see how to configure a *Management System* (**MS**) to onboard a new edge device, for this we will take advantage of Red Hat implementation:

<img align="center" src="./assets/356_RHEL_FDO_process_0823.png?raw=true">  

In our setup we will run the *Manufacturing*, *Rendezvous* and *Ownership* Server on the same machine (**MS**). This machine needs to be running RHEL 8.7+ or 9.0+.



### FDO manual setup
**1.** Install all needed [components](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/composing_installing_and_managing_rhel_for_edge_images/assembly_automatically-provisioning-and-onboarding-rhel-for-edge-devices_composing-installing-managing-rhel-for-edge-images#proc_installing-the-manufacturing-server-package_assembly_automatically-provisioning-and-onboarding-rhel-for-edge-devices)  
`$ sudo dnf install -y fdo-admin-cli fdo-manufacturing-server`  

**2.** Check that you have a service dedicated to running the all-in-one (AIO) deployment of the Servers  
`$ systemctl list-unit-files | grep fdosystemctl list-unit-files | grep fdo`  

**3.** Enable and start the aio server  
`$ sudo systemctl enable --now fdo-aio`  

**4.** Open the FDO default ports on the firewall on **MS**
   ```
   $ sudo firewall-cmd --add-port=8080-8083/tcp --permanent
   $ sudo firewall-cmd --reload
   ```
**5.** Ensure the aio server is listening on the dedicated port   

`$ sudo ss -ltnp | grep -E '^State|:808[0-3]'`  

**6.** Configuring FDO service: the specific onboarding details are handled by the service-info API server, that is part of the owner’s infrastructure (*Owner Server*).  
The service is configured using a YAML file located under in `/etc/fdo/aio/configs/serviceinfo_api_server.yml` (in case you installed the aio server).  
This is the default configuration in my case:  
```
service_info:
    initial_user: null
    files: null
    commands: null
    diskencryption_clevis: null
    additional_serviceinfo: null
    after_onboarding_reboot: false
bind: 0.0.0.0:8083
service_info_auth_token: lPsgy8eToY/AdbntrUJFfkuLZ/JYsu2mnzgrgAk839I=
admin_auth_token: K0rzxhUqz/VipP/GiDOZ8rg0sjqPank/tpbw+femxO4=
device_specific_store_driver:
    Directory:
        path: /etc/fdo/aio/stores/serviceinfo_api_devices
```  
As you can see several section are available for configuration, let's go in order (you can use an example the file located at `/usr/share/doc/fdo/serviceinfo-api-server.yml`):  
* ***initial_user***  
        As you will see in the following [section](#day-1-image-creation), when you create an OSTree RHEL image, you use a blueprint file where you can also include a "initial user" so remember to use the same username and SSH key in this configuration file.  
* ***files***   
        This section of the configuration can be used to transfer files to the device. You need to include the source and destination paths along with the permissions to be setup on the device.  
* ***commands***   
        Thanks to the commands section you can configure commands that will be run as part of the onboarding process (after copying the files of the previous section).  
        In order to configure the section, you will need to include the command followed by the args each on one line. You can also include optional boolean variables:  
        - may_fail: makes it possible to continue with the onboarding even if this command fails (default is false)  
        - return_stdout: the command will return the standard output (default is false).  
        - return_stderr: has the same effect as return_stdout but with the errors (default is false).  
* ***diskencryption_clevis***   
        If configured, it will perform a disk encryption using Clevis.  
        You need to include at least which disk or partition you want to encrypt (disk_label), and the encryption method (pin).  
        You can use either a file to save the encryption keys (which is not secure) or a Trusted Platform Module (TPM) in your device.  
* ***after_onboarding_reboot***   
        Decide if after the onboarding completed you want to reboot the device automatically.  
    
You will find a file [here](files/fdo-configs/serviceinfo-api-server.yml) which has already been customized to include some common use cases:  
* registering the device on [hybrid cloud console](https://console.redhat.com) with this [script](files/fdo-configs/register-system.sh)  
* changing the hostname of the device to one based on mac address with this [script](files/fdo-configs/change-hostname.sh)  
* apply an update to the device at startup if *rpm-ostree* update is available with this [service](files/fdo-configs/apply-update.service)  

The only task now you need to complete is change all the sections in the yaml file where you need to introduce your values (in between `<>` brackets):  
*  In order to not include the user and password directly in plain text, the script that register the system accepts the inputs as base64.
```
RED_HAT_USER=$(echo "<YOUR RED HAT USER>" | base64 )
RED_HAT_PASSWORD=$(echo "<YOUR RED HAT PASSWORD>" | base64 )
```
* make sure to change `<PATH_FILES>` to the absolute directory where you copied the files  
* change the `<SSH_PUB_KEY>` to yours  
* change `<SERVICE_TOKEN>` and `<ADMIN_TOKEN>` to the ones available in `/etc/fdo/aio/configs/serviceinfo_api_server.yml`
    
### FDO automated setup
https://github.com/empovit/fido-device-onboard-demo/tree/official-collections 

## DAY 1 - Image creation

A RHEL for Edge image is an [rpm-ostree](https://coreos.github.io/rpm-ostree/) image that includes system packages to remotely install RHEL on Edge servers.

The system packages include:
- Base OS package
- Podman as the container engine
- Additional RPM content 

Differently from RHEL images, RHEL for Edge is an immutable operating system, that is, it contains a read-only root directory with the following characteristics:
- The packages are isolated from root directory
- Package installs create layers that make it easy to rollback to previous versions
- Efficient updates to disconnected environments
- Supports multiple operating system branches and repositories
- Has a hybrid rpm-ostree package system 

This allows for scenarios like this one:  
<img align="center" src="./assets/ostree-versioning.png?raw=true">  

You can compose customized RHEL for Edge images using the RHEL [image builder tool](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/composing_installing_and_managing_rhel_for_edge_images/setting-up-image-builder_composing-installing-managing-rhel-for-edge-images#edge-installing-image-builder_setting-up-image-builder).  

We will follow for the whole exercise the approach with [no external network access](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html-single/composing_installing_and_managing_rhel_for_edge_images/index#con_non-network-based-deployments_introducing-rhel-for-edge-images).  

Composing and deploying a RHEL for Edge image in non-network-based deployments involves the following high-level steps:

- Install Image Builder  
- Using RHEL image builder, create a blueprint with customizations for RHEL for Edge image  
- Import the RHEL for Edge blueprint in Image Builder  
- Create a RHEL for Edge image embedded in an OCI container  
- Download the RHEL for Edge image file  
- Publish the RHEL for Edge commit    
- Using Image Builder, create another blueprint for RHEL for Edge Installer image  
- Create a RHEL for Edge Installer image configured to pull the commit with RHEL for Edge Container image  
- Download the RHEL for Edge Installer image  
- Run the installation on the **Edge Device**  

### Installing Image Builder

By reusing the **MS** system already configured for FDO, start installing the needed components:  

`sudo dnf install -y osbuild-composer composer-cli  bash-completion`

Remember to enable the service:  

`sudo systemctl enable osbuild-composer.socket --now`

Load the shell configuration script so that the autocomplete feature for the composer-cli command starts working immediately without reboot:  

`source /etc/bash_completion.d/composer-cli`

We will be using the CLI to create and manage the RHEL images, but you can also use Cockpit. You can install and enable it by running these commands (including opening the TCP ports if you have a Firewall installed on **MS**)
```
sudo dnf install -y cockpit-composer
sudo systemctl enable cockpit.socket --now

sudo firewall-cmd --add-service=cockpit --permanent
sudo firewall-cmd --reload
```
If you want to take a look at Cockpit just go to http://<MS_IP_ADDRESS>:9090

### Creating the RHEL for Edge image blueprint

Image Builder can create several types of RHEL for Edge artifacts, all of these are essentially a delivery mechanism for the OSTree commit. Think of this as the OS image, as it literally contains the entire operating system.  

                      ┌─────────────────┐
                      │                 │
                      │  Image Builder  │
                      │                 │
                      └────────┬────────┘
                               │
                               ▼
                       ┌───────────────┐
                       │               │
                       │ OSTree Commit │
                       │               │
                       └───────┬───────┘
                               │
             ┌─────────────────┼──────────────────┐
             │                 │                  │
     ┌───────▼───────┐  ┌──────▼──────┐   ┌───────▼───────┐
     │               │  │             │   │               │
     │ OCI Container │  │  Installer  │   │  Raw OSTree   │
     │     (tar)     │  │    (iso)    │   │     (tar)     │
     └───────────────┘  └─────────────┘   └───────────────┘


As a reference to start creating or modifying in this case a blueprint you can take a look [here](https://luisarizmendi.github.io/tutorial-secure-onboarding/fdo-tutorial/02-rfe-lab.html#rfe-ostreeimage-optiona), where all the main sections of a blueprint are documented in an excellent way.  
We will be using an example that you can find [here](files/ostree-image/blueprint-oci.toml).  
In the example *TOML* file we are:
* including cockpit packages (which we are calling during onboarding)  
* including KVM packages (so that we can deploy VM on **Edge   Device**)
* *later* including Microshift packages (to run containers on K8S)  
* opening firewall port for cockpit  
* adding an admin user (remember to use the same configured [here](#fdo-manual-setup))  

Remember to change the variables in the file with your own:
- `SSH_PUB_KEY`
- `ADMIN_PASSW` to be encrypted using 
```
python3 -c 'import crypt,getpass;pw=getpass.getpass();print(crypt.crypt(pw) if (pw==getpass.getpass("Confirm: ")) else exit())'
```

### Importing the RHEL for Edge blueprint in Image Builder  

Push the Blueprint into Image Builder pointing to the file that you created:

`sudo composer-cli blueprints push <blueprint_file>`  

You can double-check that the Blueprint is ready to be used in the Image Builder with this command:

`sudo composer-cli blueprints list`

### Creating a RHEL for Edge image 

You will need to point to the name that you gave to the Blueprint (the one that you used in the `name` parameter in the Blueprint file), not the file name.  
If you used the provided Blueprint, which name is `kvm-insights`, the command will be:

`sudo composer-cli compose start-ostree kvm-insights edge-commit`

The command will start to create the repo. You can check the status of the build by running the following command:  

`watch sudo composer-cli compose status`

You will need to wait until the status for your image changes to 'FINISHED` (which usually takes anything between 10 and 20 minutes), then the image will ready in Image Builder.


### Downloading the RHEL for Edge image

Since we used the `edge-commit` image type, you have your OSTree image in Image Builder as a TAR file but in order to use it you will need to "download" it using the following command, where the IMAGE ID is the ID generated by the Image Builder and that you can find using the command 
`sudo composer-cli compose status`:

`sudo composer-cli compose image <IMAGE_ID>`

This command will download a TAR file with all the OSTree image contents. If you are not using the root user, remember to change the file ownership:  

`sudo chown $(whoami) <IMAGE_TAR_FILE>`

### Publishing the RHEL for Edge Container commit

You eventually need to have the OSTree image/repo "published" into a HTTP server to proceed with the rest of the flow.

When you created the image in the previous section, you used the `edge-commit` image type, which means that Image Builder create the OSTree image contents and put them into a TAR file. There is another image type that you might use here, the `edge-container` type, which creates the OSTree image contents and directly creates a container image that publishes them using NGINX.   
In this lab we are going to use the first approach because this procedure can be used for either network and non-network based deployments, since you can include additional information into the container image (ie. a kickstart file) and because you will be able to manage the lifecycle of this container image (ie. image patching) which is convenient for production environments.

You are going to use a container image to publish the OSTree image so you need to have podman installed on **MS**:

`sudo dnf install -y podman`

The idea is to create a container image with NGINX, so you can customize even the NGINX configuration as part of this procedure.

You can find the NGINX config file [here](files/ostree-image/nginx.conf).  
To create the NGINX container you can use [this Dockerfile](files/ostree-image/Dockerfile). 
Now it's time to build the NGINX which includes the `edge-commit`:  

`sudo podman build -t <blueprint_name>:<image id>  --build-arg commit=<IMAGE TAR FILE> .`

To expose the NGINX publishing port outside **MS** you would first need to open the firewall (in this case we are using port 8090 not to clash with other possible commonly used services):  

```
sudo firewall-cmd --add-port=8090/tcp --permanent
sudo firewall-cmd --reload
```

Now we can finally run the build container:  

`sudo podman run --name <blueprint_name>-<image id> -d -p 8090:8080 <blueprint_name>:<image id>`

Make sure that the container is running and exposing the expected content by running:  

`curl http://<MS_IP_ADDRESS>:8090/repo/`

### Creating blueprint for RHEL for Edge Installer image
Since we want to use the Device Onboarding with FDO, we  will create an ISO image containing the OSTree repository and pointing to the FDO *Manufacturing* server so you can embed the required certificates and keys.

This new Blueprint file will need, at least, info about the disk that will be used to install the system and the FDO manufacturing URL:
- if **Edge Device** is a physical system you probably want to use something like *sda*, but if you are going to use a VM as simple edge device use *vda*
- For the FDO manufacturing server URL, you will need the IP address and the port, this depends on whether you used the all-in-one or distributed services approach before in *FDO configuration*.

You can find the new blueprint [here](files/ostree-image/blueprint-installer.toml).


### Create a RHEL for Edge Installer image  
Push again this new Blueprint file into the Image Builder:

`sudo composer-cli blueprints push blueprint-installer.toml`

And check that the new Blueprint (the name that we used is blueprint-fdo) is ready to be used in the Image Builder:  

`sudo composer-cli blueprints list`

Recall the <IMAGE_BUILDER_IP> (which should be the same as the **MS** IP) and the <IMAGE_PUBLISH_PORT> (which should be 8090 if you followed these instructions), but you will also need to include the path (URL) to the right content which depends on the RHEL release and architecture used to generate the OSTRee image.

The release and the architecture should match with the ones of the Image Builder, so you can get those values running these commands on the **Management System**:
```
baserelease=$(cat /etc/redhat-release | awk '{print $6}' | awk -F . '{print $1}')
basearch=$(arch)
```
Create the ISO file with the embedded OSTree repository:  

`sudo composer-cli compose start-ostree blueprint-fdo edge-simplified-installer --ref rhel/${baserelease}/${basearch}/edge --url http://<IMAGE_BUILDER_IP>:<IMAGE_PUBLISH_PORT>/repo/`

Once the status changes to FINISHED, the ISO image will be ready in the Image Builder, you just need to download it.

### Download the RHEL for Edge Installer image

Find the ID of the generate image with:  

`sudo watch composer-cli compose status`

Then, download the ISO file from the Image Builder using the ID and change the owner if you are not using the root user:
```
sudo composer-cli compose image <ISO_IMAGE_ID>
sudo chown $(whoami) <FDO_ISO_IMAGE_ID>-simplified-installer.iso
```

At this point you should have an ISO file (downloaded in the Image Builder) that you can use to deploy the **Edge Device**.  


## DAY 1 - Device self register
Before onboarding and installing the device, we can't forget that we also want the device to self-register to the management platforms:  
- **Ansible Automation Platform**
- **Advanced Cluster Manager**

To do that we need a brief introduction to both platforms and to include more files in the initial OSTree image commit.

### OS and platform management - Ansible
In case you want to scale and consequentyly automate your Edge operations, you might be looking for a specific tool to do that and *Ansible* might just be what you are looking for.

**Ansible Automation Platform** allows platform engineering and DevOps teams to create, manage, and scale automation across physical, cloud, virtual, and edge environments. With Ansible Automation Platform, you can drive consistency and manage compliance with automated workflows that span infrastructure, network components, applications, storage, security, ITSM, and more.

You can create automation code using simple, YAML-based syntax supported by our full suite of Ansible features, tools, and components.  

These are the main components of **AAP**:  
<img align="center" src="./assets/automation-controller.png?raw=true">  

**Event Driven Ansible** is one of the components of **AAP**.  **EDA** connects intelligent sources of events with corresponding actions via rules. Ansible Rulebooks define the event source and explain, in the form of conditional “if-this-then-that” statements, the action to take when the event occurs. Based on the rulebook you design, **EDA** recognizes the specified event, matches it with the appropriate action, and automatically executes it.

This is how **EDA** works:
<img align="center" src="./assets/eda-01.png?raw=true">  

For this scenario you will need an **AAP** with **EDA** installed to receive the call (this can be on the same **MS** machine or not).

#### ADDENDUM to FDO manual setup  
We would then need to add a script and a service that perform **Edge Device** registration to **AAP** inventory leveraging **EDA** to the *serviceinfo-api-server.yml* file (so that these are run at startup):
- [registration script](files/fdo-configs/ansible-auto-registration.sh):  
  which will send the IP address and MAC address of the onboarded **Edge Device** to **EDA** (make sure to change the <ANSIBLE_HOST> variable)
- [registration service](files/fdo-configs/ansible-auto-registration.service):  
  which will call the script above only after connection is available

#### AAP & EDA setup
We would also need to introduce the Ansible logic, to take care of the registration flow.  
All objects that **AAP** and **EDA** will use need to be versioned in a repository.  

1. So we will start by creating 2 different repos, 1 for **AAP** configurations and 1 for **EDA** configurations (you can use GitHub as system credentials will not be saved in the YAML files).  
2. Create an *Organization* on **AAP** like [this](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/automation_controller_user_guide/assembly-controller-organizations#proc-controller-create-organization)  
3. We will setup credentials to authenticate to both repos:  
   1. **EDA**: [reference](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/event-driven_ansible_controller_user_guide/eda-credentials#eda-set-up-credential)  
   2. **AAP**: [reference](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/automation_controller_user_guide/controller-projects#proc-scm-git-subversion)
4. Create projects in both platforms:  
   1. **EDA**: [reference](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/event-driven_ansible_controller_user_guide/eda-projects)  
   2. **AAP**: [reference](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/automation_controller_user_guide/controller-projects#proc-controller-adding-a-project)  
5. Create a `Decision Environment`: this is a container that will run the Ansible rulebook: [reference](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/event-driven_ansible_controller_user_guide/eda-decision-environments#eda-set-up-new-decision-environment). You can use the default `Decision Environment` container available at `registry.redhat.io/ansible-automation-platform-24/de-supported-rhel9`   
6. Create a `Rulebook activation`: the rulebook activation is a process running in the background defined by a `Decision Environment` executing a specific rulebook. [reference](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/event-driven_ansible_controller_user_guide/eda-rulebook-activations)  
7. Setup **EDA** to **AAP** authentication like [this](https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.4/html/event-driven_ansible_controller_user_guide/eda-set-up-token#eda-set-up-token-to-authenticate) 
8. We can now push the *Rulebook* containing the logic triggering **AAP** automation to the repo we created for **EDA**. You will need to create a `rulebooks` folder and add the [rulebook](files/aap/rulebooks/eda-rulebook.yml) there. The only `rule` you should care about is the last one for the moment: *Initial provisioning*. Make sure to change the variable `<YOUR_ORG>` with your *Organization* on **AAP**.  
9. Sync the project in **EDA**.  
10. Expose the created `Service` in OpenShift related to the `Rulebook Activation` with a `Route`.  
11. Create 2 *Inventory* in **AAP**. The first one is an empty inventory to be populated automatically, just make sure to call it `Edge Devices`. Create also a `Local Actions` inventory dedicated to handling call towards **AAP** itself. Add a `host` like shown in the picture.  
12. Create *Device credentials* to authenticate to the **Edge Device**. In this case we are going to use the same username and password that was added to this [file](files/ostree-image/blueprint-oci.toml).  Create also a *Controller API Credentials* to make sure you can perform API calls to **AAP** inside the playbooks (you can reuse the same admin user credentials).  
13. Use as `Execution Environment` this [one](quay.io/luisarizmendi/provisioner-execution-environment:latest) in **AAP** configuration. Make sure to use this one to execute all `Jobs` and `Workflows` in this tutorial.  
14. Push the 3 files under [playbooks](files/aap/playbooks/) folder to the **AAP** repo, inside a `playbooks` folder (make sure to change the variables to reference your organization and project). Sync the project.
15. Create 3 *Job templates* in **AAP** following the structure of [this](files/aap/jobs-templates/controller-templates.yml).  
16. Create the *Workflow template* on **AAP** following  [this](files/aap/workflows/controller-workflow.yml). Then create the template with the wizard. You should have in the end a flow similar to the one in the picture.  
17. You can test if the flow works by manually activating the **EDA** endpoint with a command similar to this one:
```
JSON="{\                    
\"ip_address\": \"192.168.1.111\", \
\"mac_address\": \"aabbccddeeff\" \
}"
curl -H 'Content-Type: application/json' --data "$JSON" http://<YOUR_EDA_ACTIVATION_URL>
```
     

### Application Management - ACM
In the case of containerized application we want to take advantage of using Microshift, which is part of Red Hat Device Edge.  
The Red Hat build of MicroShift is a lightweight Kubernetes container orchestration solution built from the edge capabilities of Red Hat OpenShift and based on the open source community’s project by the same name.  
We are going to manage *Microshift* using **ACM**.  

Red Hat **Advanced Cluster Management** (**ACM**) for Kubernetes provides end-to-end management visibility and control to manage your Kubernetes environment. You can take control of your application modernization program with management capabilities for cluster creation, application lifecycle, and provide security and compliance for all of them across hybrid cloud environments. Clusters and applications are all visible and managed from a single console, with built-in security policies.


#### ADDENDUM to FDO manual setup  
Since we want to include *Microshift* in the base image that we build we are going to modify this [file](files/ostree-image/blueprint-oci.toml) once again to include the needed packages.  
You can use as an example the *Blueprint* that comes with *Microshift* RPM: `microshift-release-info`.  
```
$ sudo dnf install -y microshift-release-info
$ cat /usr/share/microshift/blueprint/blueprint-x86_64.toml 
```
You can find the example *Blueprint* [here](files/ostree-image/blueprint-microshift.toml).  
We would now merge the two blueprints in a single file that you can find [here](files/ostree-image/blueprint-final.toml). We will call it `microshift-kvm-insights`.  

You also need to add the service to let *Microshift* register itself to **ACM**. The documentation for this step can be found [here](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.7/html-single/apis/index#rhacm-docs_apis_cluster_jsoncreatecluster).  
You have to include 3 new files in the `serviceinfo-api-server`config:
1. [script](files/fdo-configs/acm.auto-registration.sh) to register microshift to acm: make sure to change the variable `<YOUR_ACM_TOKEN>` with a generated `OpenShift` access token with cluster-admin rights. Change also the `<YOUR_ACM_HOST>` variable with yours. 
2. associated system [service](files/fdo-configs/acm-auto-registration.service)  
3. The `pull-secret`: you can download your installation pull secret from the [Red Hat Hybrid Cloud Console](https://console.redhat.com/), you can see which filename to use [here](files/fdo-configs/serviceinfo-api-server.yml#L44). This pull secret allows you to authenticate with the Red Hat container registries that serve the container images used by Red Hat build of MicroShift.  



#### ADDENDUM to Image Builder
On the system that is handling image building (**MS**) you would need to add a pull secret for authenticating to the registry and being able to pull the images during the image building process.  To do so, set the `auth_file_path` in the `[containers]` section of the osbuilder worker configuration in `/etc/osbuild-worker/osbuild-worker.toml` (you might need to create directory and file).
```
[containers]
auth_file_path = "/etc/osbuild-worker/pull-secret.json"
```
You need to restart the osbuild-worker when you changed that configuration using `sudo systemctl restart osbuild-worker@1`

You would also need to add 2 RPM repos that are needed to install `Microshift`:  
- [rhocp](files/ostree-image/additional-repos/rhocp-4.15.toml)
- [fast-datapath](files/ostree-image/additional-repos/fast-datapath.toml)

Make sure to run the following commands before adding the above repos:  
```
baserelease=$(cat /etc/redhat-release | awk '{print $6}' | awk -F . '{print $1}')
basearch=$(arch)
```
Make sure to substitute the 2 values above inside the 2 rpm repo toml files.

And add the repos like this:
```
$ sudo composer-cli sources add rhocp-4.15.toml
$ sudo composer-cli sources info rhocp-4.15
$ sudo composer-cli sources add fast-datapath.toml
$ sudo composer-cli sources info fast-datapath
```
! microshift 4.12 https://access.redhat.com/documentation/en-us/red_hat_build_of_microshift/4.12/html/installing/microshift-embed-in-rpm-ostree#preparing-for-image-building_microshift-embed-in-rpm-ostree -> not working
! this one: https://github.com/redhat-et/microshift-demos/tree/main

## DAY 1 - EXECUTION - Device onboarding and installation
For FDO onbaording to work, the *Edge Device* (**ED**) has to have a Trusted Platform Module (TPM) device to encrypt the keys for the onboarding process.
https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/composing_installing_and_managing_rhel_for_edge_images/assembly_automatically-provisioning-and-onboarding-rhel-for-edge-devices_composing-installing-managing-rhel-for-edge-images#con_automatically-provisioning-and-onboarding-rhel-for-edge-devices_assembly_automatically-provisioning-and-onboarding-rhel-for-edge-devices

Recap of the steps:
1. Install *Image Builder* [here](#installing-image-builder)
2. Enable additional repo [here](#addendum-to-fdo-manual-setup-1)
3. Copy and modify the FDO scripts to the *Image Builder* [here](#fdo-manual-setup). Change the base FDO config with the one just modified and restart the FDO server(s) (if you used the AIO approach the file shoulbd be under `/etc/fdo/aio/configs/`). Restart the service with `sudo systemctl restart fdo-aio`.  
4. Modify and import the final image blueprint [here](#importing-the-rhel-for-edge-blueprint-in-image-builder). Remember to change also the variables in the ACM and Ansible registration [script](files/fdo-configs/acm-auto-registration.sh#L16) and [script](files/fdo-configs/ansible-auto-registration.sh#L19). The `HOST` URL can be found under the *multicluster-engine* project.  
5. Create OSTree image [here](#creating-a-rhel-for-edge-image)
6. Download and publish the image commit [here](#downloading-the-rhel-for-edge-image). For the [publishing](#publishing-the-rhel-for-edge-container-commit) step remember to use the Dockerfile provided for the build and the created `nginx.conf`file.  
7. After modifying the [blueprint](#creating-blueprint-for-rhel-for-edge-installer-image) for the installer image push it to the *Image Builder*  
8. Create the OSTree install ISO [here](#create-a-rhel-for-edge-installer-image). 
9. Download the generated ISO file [here](#download-the-rhel-for-edge-installer-image)  
10. Create a VM (or use a physical machine) that will act as **Edge Device**. Use the FDO enabled RHEL OSTree ISO image to install the **ED**. Review the onboarding process and completion.  

As reference for the VM you can use this command, (remember to add a virtual or passthorugh TPM):  
```
virt-install --name=edge-device \
--vcpus=2 \
--memory=1536 \
--cdrom=<PATH TO RHEL OSTREE ISO> \
--disk size=20 \
--os-variant=rhel9.1 \
--boot uefi \
--tpm backend.type=emulator,backend.version=2.0,model=tpm-crb
```
Make sure you are booting the **Edge Device** as UEFI and not BIOS.  



## DAY 2 - Application deployment PUSH
using ACM

## DAY 2 - Application deployment PULL
usig gitops microshift approach

## DAY 2 - Device update (and rollback)


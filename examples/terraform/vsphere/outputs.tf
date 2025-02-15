/*
Copyright 2019 The KubeOne Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

output "kubeone_api" {
  description = "kube-apiserver LB endpoint"

  value = {
    endpoint = "${vsphere_virtual_machine.lb.default_ip_address}"
  }
}

output "kubeone_hosts" {
  description = "Control plane endpoints to SSH to"

  value = {
    control_plane = {
      cluster_name         = "${var.cluster_name}"
      cloud_provider       = "vsphere"
      private_address      = []
      public_address       = "${vsphere_virtual_machine.control_plane.*.default_ip_address}"
      ssh_agent_socket     = "${var.ssh_agent_socket}"
      ssh_port             = "${var.ssh_port}"
      ssh_private_key_file = "${var.ssh_private_key_file}"
      ssh_user             = "${var.ssh_username}"
    }
  }
}

output "kubeone_workers" {
  description = "Workers definitions, that will be transformed into MachineDeployment object"

  value = {
    # following outputs will be parsed by kubeone and automatically merged into
    # corresponding (by name) worker definition
    pool1 = {
      replicas        = 1
      sshPublicKeys   = ["${file("${var.ssh_public_key_file}")}"]
      operatingSystem = "${var.worker_os}"

      operatingSystemSpec = {
        distUpgradeOnBoot = false
      }

      # provider specific fields:
      # see example under `cloudProviderSpec` section at: 
      # https://github.com/kubermatic/machine-controller/blob/master/examples/vsphere-machinedeployment.yaml

      allowInsecure  = false
      cluster        = "${var.compute_cluster_name}"
      cpus           = 2
      datacenter     = "${var.dc_name}"
      datastore      = "${var.datastore_name}"
      # Optional: Resize the root disk to this size. Must be bigger than the existing size
      # Default is to leave the disk at the same size as the template
      diskSizeGB     = 10
      memoryMB       = 2048
      templateVMName = "${var.template_name}"
      vmNetName      = "${var.network_name}"
    }
  }
}

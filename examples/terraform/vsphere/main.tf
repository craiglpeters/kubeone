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

provider "vsphere" {
  /*
  See https://www.terraform.io/docs/providers/vsphere/index.html#argument-reference
  for config options reference
  */
}

data "vsphere_datacenter" "dc" {
  name = "${var.dc_name}"
}

data "vsphere_datastore" "datastore" {
  name          = "${var.datastore_name}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_compute_cluster" "cluster" {
  name          = "${var.compute_cluster_name}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = "${var.network_name}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "${var.template_name}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

resource "vsphere_virtual_machine" "control_plane" {
  count            = 3
  name             = "${var.cluster_name}-cp-${count.index + 1}"
  resource_pool_id = "${data.vsphere_compute_cluster.cluster.resource_pool_id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"
  num_cpus         = 2
  memory           = 2048
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "disk0"
    size             = "${var.disk_size}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"
  }

  vapp {
    properties {
      hostname    = "${var.cluster_name}-cp-${count.index + 1}"
      public-keys = "${file("${var.ssh_public_key_file}")}"
    }
  }

  lifecycle {
    ignore_changes = [
      "vapp.0.properties",
      "tags",
    ]
  }
}

resource "vsphere_virtual_machine" "lb" {
  count            = 1
  name             = "${var.cluster_name}-lb-${count.index + 1}"
  resource_pool_id = "${data.vsphere_compute_cluster.cluster.resource_pool_id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"
  num_cpus         = 1
  memory           = 1024
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "disk0"
    size             = "${var.disk_size}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
  }

  cdrom {
    client_device = true
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"
  }

  vapp {
    properties {
      hostname    = "${var.cluster_name}-lb-${count.index + 1}"
      public-keys = "${file("${var.ssh_public_key_file}")}"
    }
  }

  lifecycle {
    ignore_changes = [
      "vapp.0.properties",
      "tags",
    ]
  }

  connection {
    host = "${self.default_ip_address}"
    user = "${var.ssh_username}"
  }

  provisioner "remote-exec" {
    script = "gobetween.sh"
  }
}

data "template_file" "lbconfig" {
  template = "${file("etc_gobetween.tpl")}"

  vars = {
    lb_target1 = "${vsphere_virtual_machine.control_plane.0.default_ip_address}"
    lb_target2 = "${vsphere_virtual_machine.control_plane.1.default_ip_address}"
    lb_target3 = "${vsphere_virtual_machine.control_plane.2.default_ip_address}"
  }
}

resource "null_resource" "lb_config" {
  triggers = {
    cluster_instance_ids = "${join(",", vsphere_virtual_machine.control_plane.*.id)}"
    config               = "${data.template_file.lbconfig.rendered}"
  }

  connection {
    user = "${var.ssh_username}"
    host = "${vsphere_virtual_machine.lb.default_ip_address}"
  }

  provisioner "file" {
    content     = "${data.template_file.lbconfig.rendered}"
    destination = "/tmp/gobetween.toml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/gobetween.toml /etc/gobetween.toml",
      "sudo systemctl restart gobetween",
    ]
  }
}

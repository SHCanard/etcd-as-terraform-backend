# Set terraform backend on etcdv3
terraform {
  backend "etcdv3" {
    endpoints = ["https://server01:2379", "https://server02:2379", "https://server03:2379"]
    lock      = true
    prefix    = "vcenter/domain/project/"
  }
}

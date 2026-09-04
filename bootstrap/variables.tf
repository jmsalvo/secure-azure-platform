variable "location" {
  description = "Azure region for the bootstrap resource group and storage account."
  type        = string
  default     = "eastus2"
}

variable "github_repository" {
  description = "GitHub \"owner/repo\" the OIDC federated credentials trust, for example \"jmsalvo/secure-azure-platform\"."
  type        = string
}

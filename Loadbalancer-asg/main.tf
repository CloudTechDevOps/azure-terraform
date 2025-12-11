## While creating the soure vm security type should be standard
## while creating the image version also security type should be standard
## image type should be generalized

provider "azurerm" {
  features {}
  subscription_id = "86199285-19af-4698-a87a-520f86bd0cfd"
}

# --------------------
# Resource Group Lookup
# --------------------
data "azurerm_resource_group" "rg" {
  name = "loadbalencer"
}

# --------------------
# Virtual Network & Subnets
# --------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-terraform"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet_vmss" {
  name                 = "subnet-vmss-terraform"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rg.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "subnet_appgw" {
  name                 = "subnet-appgw-tf"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rg.name
  address_prefixes     = ["10.0.2.0/24"]
}

# --------------------
# Network Security Group
# --------------------
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-web-tf"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet_network_security_group_association" "attach" {
  subnet_id                 = azurerm_subnet.subnet_vmss.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --------------------
# Public IP for Application Gateway
# --------------------
resource "azurerm_public_ip" "appgw_pip" {
  name                = "public-ip-tf"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# --------------------
# Shared Image Gallery
# --------------------
data "azurerm_shared_image_gallery" "sig" {
  name                = "galary"
  resource_group_name = "loadbalencer"
}

data "azurerm_shared_image_version" "img" {
  name                = "0.0.1"
  image_name          = "vsvv"
  gallery_name        = data.azurerm_shared_image_gallery.sig.name
  resource_group_name = data.azurerm_shared_image_gallery.sig.resource_group_name
}

# --------------------
# VM Scale Set
# --------------------
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "vmss-veera-tf"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = "Standard_D2ls_v6"
  instances           = 1

  admin_username = "adminuser"
  admin_password = "Akki@12345678"
  disable_password_authentication = false

  source_image_id = data.azurerm_shared_image_version.img.id

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnet_vmss.id

      # ✔ Correct way to attach backend pool (NO INDEXING)
      application_gateway_backend_address_pool_ids = [
        for pool in azurerm_application_gateway.appgw.backend_address_pool : pool.id
      ]
    }
  }
}



# --------------------
# Application Gateway (WAF)
# --------------------
resource "azurerm_application_gateway" "appgw" {
  name                = "appgw-veera-tf"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.subnet_appgw.id
  }

  frontend_port {
    name = "frontend-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name = "backend-pool"
  }

  backend_http_settings {
    name                  = "http-settings"
    port                  = 80
    protocol              = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 30
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "frontend-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule"
    rule_type                  = "Basic"
    http_listener_name         = "listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }
}


# --------------------
# Autoscale
# --------------------
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "vmss-autoscale-veeraa-tf"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id

  profile {
    name = "default"

    capacity {
      minimum = 1
      maximum = 5
      default = 1
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        operator           = "GreaterThan"
        statistic          = "Average"
        threshold          = 70
        time_grain         = "PT1M"
        time_window        = "PT5M"
        time_aggregation   = "Average"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        operator           = "LessThan"
        statistic          = "Average"
        threshold          = 30
        time_grain         = "PT1M"
        time_window        = "PT5M"
        time_aggregation   = "Average"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }
  }
}

# --------------------
# Output
# --------------------
output "application_gateway_url" {
  value = "http://${azurerm_public_ip.appgw_pip.ip_address}"
}



provider "azurerm" {
  features {}
  subscription_id = "9734ed68-621d-47ed-babd-269110dbacb1"
   resource_provider_registrations = "none"
}

# --------------------
# Resource Group Lookup
# --------------------
data "azurerm_resource_group" "rg" {
  name = "1-17270391-playground-sandbox"
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

# VMSS launch servers into thi subnet and inside multiple Az 
resource "azurerm_subnet" "subnet_vmss" {
  name                 = "subnet-vmss-terraform"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = data.azurerm_resource_group.rg.name
  address_prefixes     = ["10.0.1.0/24"]
}

#Dedicated subnet required for App gateway 
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
# Public IP for Application Gateway if it is external facing 
# --------------------
resource "azurerm_public_ip" "appgw_pip" {
  name                = "public-ip-tf"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}



# VM Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "veera-vmms-cloud"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Standard_B2s"
  instances           = "2"
  admin_username = "adminuser"
  admin_password = "Akki@12345678"
  disable_password_authentication = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary  = true
      subnet_id = azurerm_subnet.subnet_vmss.id
    }
  }

  upgrade_mode = "Automatic"

  tags = {
    environment = "dev"
  }
}


# --------------------
# Application Gateway
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
# Autoscale VMSS
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
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "vmss-linux"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "Standard_B2s"
  instances           = 1
  admin_username      = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary  = true
      subnet_id = azurerm_subnet.vmss.id

      # ✅ THIS enables auto registration with App Gateway
      application_gateway_backend_address_pool_ids = [
        azurerm_application_gateway.appgw.backend_address_pool[0].id
      ]
    }
  }
}

#az login --use-device-code

# 1. Create Resource Group
# resource "azurerm_resource_group" "rg" {
#   name     = "myResourceGroup"
#   location = "East US"
# }

#
# 1.Data block: reference an existing resource group
data "azurerm_resource_group" "rg" {
  name = "1-1f31e6ca-playground-sandbox"
}

# 2.Virtual network using that existing RG
resource "azurerm_virtual_network" "vnet" {
  name                = "myVNettt"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}
# 3. Create Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "mySubnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 4. Create Public IP for VM
resource "azurerm_public_ip" "public_ip" {
  name                = "vmPublicIP"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  allocation_method   = "Static"  # Change from "Dynamic" to "Static"
  sku                 = "Standard" # Ensure Standard SKU is specified
}


# 5. Create Network Security Group (NSG) and Allow SSH (Port 22)
resource "azurerm_network_security_group" "nsg" {
  name                = "vmNSG"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 6. Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 7. Create Network Interface (NIC)
resource "azurerm_network_interface" "nic" {
  name                = "vmNIC"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    public_ip_address_id          = azurerm_public_ip.public_ip.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 8. Create Virtual Machine (VM)
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "myVM"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  network_interface_ids = [azurerm_network_interface.nic.id]

  disable_password_authentication = false
  admin_password = "Akki@1212"


#   admin_ssh_key {
#     username   = "azureuser"
#     public_key = file("~/.ssh/id_rsa.pub")  # Path to your SSH public key
#   }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

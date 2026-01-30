# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "gusztavvargadr/windows-server-2022-standard"
  
  config.vm.provider "vmware_desktop" do |vb|
    vb.vmx["displayName"] = "cuda-wheel-builder"
    vb.vmx["memsize"] = "32768"
    vb.vmx["numvcpus"] = "16"
    vb.gui = false
  end
  
  # Single shared folder for output
  config.vm.synced_folder "./output", "/output", create: true
  
  # Provision
  config.vm.provision "shell", path: "./output/provision.ps1"
end
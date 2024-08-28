####
#### install kubectx (kubens)
#### https://stackoverflow.com/questions/69070582/how-can-i-install-kubectx-on-ubuntu-linux-20-04
####
###cat << EOF >> /etc/apt/sources.list
###deb [trusted=yes] http://ftp.de.debian.org/debian buster main
###EOF
apt-get update
apt install -y kubectx
#
# needed for CNI plugin install
#
apt install -y golang-go

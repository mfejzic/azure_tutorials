#cloud-config
package_upgrade: true
packages:
    - nginx
runcmd:
 - cd /var/www
 - sudo chmod 0757 html
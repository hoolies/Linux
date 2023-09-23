# Ubiquiti Adopter
## About
This is a script that will allow you to find all the ubiquiti devices in your network and adopt them
## Issue
I bought a new AP, my controller is hosted on a container at a Raspeberry Pi 4.
I forgot that I had re-image the Pi and I was missing the controller.

### Create the controller
I created a new container by running the following:
```
docker run -d --init \
   --restart=unless-stopped \
   -p 8080:8080 -p 8443:8443 -p 3478:3478/udp \
   -v ~/unifi:/unifi \
   --user unifi \
   --name unifi \
   jacobalberty/unifi:latest
```
### Restore settings from backup

But I could not find any devices.
Then I reset them to the default settings and I could not find them.
I had to adopt them manually.
I have acreated a script so I do not have to do it again.

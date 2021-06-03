# Tangible

Connecting to the real world.

## VSCode

- Run `sudo chmod a+rw /dev/ttyACM0` to give permission to read serial port.
- Keep setting the Baud Rate to recieve Serial Output after upload.

## Tunnel

- [Get ip](https://www.google.com/search?q=what+is+my+ip+address)
  - `86.132.139.177` June 3, 2020
- Log in to router to foward 80/443
  - BT routers have admin IP of `192.168.1.254`
- Add A record for domain to IP
- Nginx
  - requires a nginx.conf, must have events section
  - `nginx -t && nginx -s reload`
  - Fetch a let's encrypt certificate.
    - https://www.nginx.com/blog/using-free-ssltls-certificates-from-lets-encrypt-with-nginx/
    - `certbot --nginx -d example.com`

https://askubuntu.com/questions/630053/make-domain-name-point-to-home-server

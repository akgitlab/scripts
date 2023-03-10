vCert
July 25, 2022|vCenter, vSphere
I got a copy of this program from VMware through an SR when they helped a customer of mine. It is called vCert. This little program is super simple to use and works pretty great. It does everything and anything to do with Certificates on your vCenters. Unfortunately, VMware has not made this public yet. I wish they would.

Works on 6.x and 7.x vCenter.

***With that said, use at your own risk. This is not supported by VMware Engineering. I recommend cold snaps on everything in your SSO Domain before you change anything.***



How to set up vCert!



1. Grab a copy of the vCert from here: https://tinyurl.com/yc3w8nd9

2. SSH to your vCenter.

3. cd /home/root

4. vi vCert

5. Copy the text from the file you downloaded to the vCert file you just created. Your line count should be 4004.

6. Save the file  :wq

7. Make the file executable: chmod +x vCert

8. Run the program: ./vCert



Menu options:  

1. Check current certificates status

2. Check CA certificates in VMDir and VECS

3. View Certificate Info

4. Generate certificate report

5. Check SSL Trust Anchors

6. Update SSL Trust Anchors

7. Replace the Machine SSL certificate

8. Replace the Solution User certificates

9. Replace the VMCA certificate and re-issue Machine SSL

   and Solution User certificates

10. Replace the Authentication Proxy certificate

11. Replace the Auto Deploy CA certificate

12. Replace the VMware Directory Service certificate

13. Replace the SSO STS Signing certificate(s)

14. Replace all certificates with VMCA-signed

   certificates

15. Clear all certificates in the BACKUP_STORE

   in VECS

16. Check vCenter Extension thumbprints

17. Check for SSL Interception

18. Check STS server certificate configuration

19. Check Smart Card authentication configuration

20. Restart reverse proxy service

21. Restart all VMware services

E. Exit



I find I mostly use options 1, 6, and 14.



I hope this helps!

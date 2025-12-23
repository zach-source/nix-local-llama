# Duo Enrollment Guide

After installing Duo, each user must complete enrollment before they can use push authentication.

## Quick Enrollment Steps

1. **SSH to the machine as your user:**
   ```bash
   ssh ztaylor@ztaylor-gtr-pro.local
   ```

2. **Run sudo interactively:**
   ```bash
   sudo whoami
   ```

3. **Duo will display an enrollment URL like:**
   ```
   Please enroll at https://api-XXXXXXXX.duosecurity.com/portal?code=XXXXXXXXXX
   ```

4. **Open the URL in your browser and follow the steps:**
   - Install the Duo Mobile app on your phone
   - Scan the QR code with Duo Mobile
   - Complete the setup

5. **After enrollment, run sudo again:**
   - You'll receive a push notification on your phone
   - Approve it to complete authentication

## Troubleshooting

### "User enrollment required" error
This means you haven't enrolled yet. Follow steps 1-4 above.

### Not receiving push notifications
- Ensure your phone has internet connectivity
- Check that Duo Mobile app is installed and configured
- Verify your device is registered in your Duo account

### Bypass Duo (emergency)
The `nixbot` user is configured to bypass Duo for emergency access:
```bash
ssh nixbot@ztaylor-gtr-pro.local
sudo -u root <command>
```

## Technical Details

- **PAM Module**: `/usr/lib/security/pam_duo.so`
- **Config**: `/etc/duo/pam_duo.conf`
- **Failmode**: `safe` (allows login if Duo unreachable)
- **Autopush**: `yes` (sends push automatically)

## Enrolling Additional Users

Each user who needs to use sudo must complete their own enrollment process.
The enrollment is tied to the Unix username.

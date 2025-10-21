#!/bin/sh

DEFAULT_KINDLE_IP="192.168.10.94"
KINDLE_IP=${1:-$DEFAULT_KINDLE_IP}
PACKAGE_NAME="namible_deploy"
TMP_DIR="/tmp/${PACKAGE_NAME}"

echo "Preparing deployment package..."

# 1. Create a temporary local directory to stage the files.
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/apps" "$TMP_DIR/extensions"

# 2. Copy all project files into the staging directory.
cp -r src/apps/namible "$TMP_DIR/apps/"
cp -r src/extensions/namible "$TMP_DIR/extensions/"

# 3. Create the on-device installer script.
cat > "$TMP_DIR/install.sh" << EOF
#!/bin/sh
echo "Updating Namible on Kindle..."

# Ensure the target directories exist.
mkdir -p /mnt/us/apps/namible
mkdir -p /mnt/us/extensions/namible

# Copy the new files, overwriting old ones but leaving existing binaries untouched.
# The '*' is crucial to copy the contents, not the directory itself.
cp -r "/tmp/${PACKAGE_NAME}/apps/namible/"* /mnt/us/apps/namible/
cp -r "/tmp/${PACKAGE_NAME}/extensions/namible/"* /mnt/us/extensions/namible/

# Set executable permissions on the updated scripts.
chmod +x /mnt/us/apps/namible/*.sh

echo "Update complete."
EOF

echo "Deploying to ${KINDLE_IP}..."

# 4. Tar the staging directory and pipe it directly over SSH to be extracted on the Kindle.
# The remote command then runs the installer and cleans up. This requires only one password entry.
tar -cz -C "/tmp" "$PACKAGE_NAME" | ssh "root@${KINDLE_IP}" "
    tar -xz -C /tmp &&
    sh /tmp/${PACKAGE_NAME}/install.sh &&
    rm -rf /tmp/${PACKAGE_NAME}
"

# 5. Clean up the local staging directory.
rm -rf "$TMP_DIR"

echo "Deployment finished."

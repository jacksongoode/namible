#!/bin/sh

DEFAULT_KINDLE_IP="192.168.10.94"
KINDLE_IP=${1:-$DEFAULT_KINDLE_IP}
PACKAGE_NAME="namible_deploy"
TMP_DIR="/tmp/${PACKAGE_NAME}"

echo "--- Preparing Deployment Package ---"

# 1. Create a temporary local directory to stage the files.
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/apps" "$TMP_DIR/extensions" "$TMP_DIR/documents"

# 2. Copy all project files into the staging directory.
cp -r apps_to_deploy/namible "$TMP_DIR/apps/"
cp -r extensions_to_deploy/namible "$TMP_DIR/extensions/"
cp -r Namible.azw2 "$TMP_DIR/documents/"

# 3. Create the on-device installer script.
cat > "$TMP_DIR/install.sh" << EOF
#!/bin/sh
echo "--- Updating Namible on Kindle (non-destructive) ---"

# Ensure the target directories exist.
mkdir -p /mnt/us/apps/namible
mkdir -p /mnt/us/extensions/namible
mkdir -p /mnt/us/documents/Namible.azw2

# Copy the new files, overwriting old ones but leaving existing binaries untouched.
# The '*' is crucial to copy the contents, not the directory itself.
cp -r "/tmp/${PACKAGE_NAME}/apps/namible/"* /mnt/us/apps/namible/
cp -r "/tmp/${PACKAGE_NAME}/extensions/namible/"* /mnt/us/extensions/namible/
cp -r "/tmp/${PACKAGE_NAME}/documents/Namible.azw2/"* /mnt/us/documents/Namible.azw2/

# Set executable permissions on the updated scripts.
chmod +x /mnt/us/apps/namible/*.sh /mnt/us/documents/Namible.azw2/launch.sh

echo "--- Update Complete ---"
EOF

# 4. Create a compressed tarball of the staging directory.
tar -czf "${PACKAGE_NAME}.tar.gz" -C "/tmp" "$PACKAGE_NAME"

# 5. Clean up the local staging directory.
rm -rf "$TMP_DIR"

echo "--- Deploying to ${KINDLE_IP} ---"

# 6. Use a single SCP call to upload the package.
scp "${PACKAGE_NAME}.tar.gz" "root@${KINDLE_IP}:/tmp/"

# 7. Use a single SSH call to extract, install, and clean up on the Kindle.
ssh "root@${KINDLE_IP}" << EOF
# Extract the archive in the temp directory.
tar -xzf "/tmp/${PACKAGE_NAME}.tar.gz" -C "/tmp"
# Run the installer.
sh "/tmp/${PACKAGE_NAME}/install.sh"
# Clean up the temporary files on the Kindle.
rm -rf "/tmp/${PACKAGE_NAME}" "/tmp/${PACKAGE_NAME}.tar.gz"
EOF

# 8. Clean up the local tarball.
rm -f "${PACKAGE_NAME}.tar.gz"

echo "--- Deployment Finished ---"

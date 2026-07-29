#!/bin/sh
# Wrapper script for binary-sign-tool.jar
# Usage: binary-sign-tool sign -inFile <input> -outFile <output> -selfSign 1
exec java -jar /opt/binary-sign-tool/binary-sign-tool.jar "$@"

Let's create a script that can be run on OSX 15.6.1 or later. The ending result, after running the script is for the apps to be installed, with minimal if any user interaction. In additional the zshrc_modification should be added to the zshrc file

Please adhere to the following criteria:
1. It MUST be idempotent. So if an app is already installed, then don't try to download and install it again
2. The zshrc modifications MUST also be idempotent
3. The script MUST take some input files to know what zshrc modifications to apply and apps to install. Some options: Use the input files in the `Details/` directory, or some other easier to use structured format.
4. There SHOULD be an argument to indicate whether the personal apps should be installed
5. There SHOULD be an optional argument to cleanup old installers that are no longer needed.
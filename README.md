# NetCtl 🚀

NetCtl is an open-source, ready-to-run service that effortlessly exposes your localhost to the internet. Powered by SSH, it runs in the background and is fully controllable via simple commands—perfect for developers and remote access enthusiasts alike.

## Installation 📥

### 1. Using curl (or wget)

Download the NetCtl script directly to `/bin/netctl` and make it executable:

#### With curl

```bash
sudo curl -L https://raw.githubusercontent.com/yourusername/netctl/main/netctl.sh -o /bin/netctl
sudo chmod +x /bin/netctl
```

#### With wget

```bash
sudo wget https://raw.githubusercontent.com/yourusername/netctl/main/netctl.sh -O /bin/netctl
sudo chmod +x /bin/netctl
```

### 2. Using Git Clone

Alternatively, clone the repository and install NetCtl manually:

```bash
git clone https://github.com/yourusername/netctl.git
cd netctl
sudo cp netctl.sh /bin/netctl
sudo chmod +x /bin/netctl
```

Now, you can run `netctl` from anywhere on your system!

## Features ✨

- **Open Source & Ready to Use** 🔓  
  Easily add your localhost to the internet with a powerful, open-source service.
- **SSH-Powered Tunneling** 🔀  
  Create secure tunnels via SSH that run quietly in the background.
- **Dynamic Connection Management** 🛑  
  List, stop, and control active connections with simple commands.
- **Automatic Dependency Handling** 🛠️  
  Detects your OS and installs required packages automatically.
- **Shell Auto-Completion** ⌨️  
  Enjoy a seamless command-line experience with dynamic completions.

## Usage 🚀

- **Save a Token:**  
  Save your API token to enable tunneling.
  ```bash
  netctl token YOUR_API_TOKEN_HERE
  ```

- **Start a TCP Tunnel:**  
  Open a tunnel on the specified local port.
  ```bash
  netctl tcp 8080
  ```

- **Start an HTTP Tunnel (without Custom Domain):**  
  Open an HTTP tunnel on the specified port.
  ```bash
  netctl http 8000
  ```

- **Start an HTTP Tunnel with a Custom Domain:**  
  Open an HTTP tunnel and specify your custom domain.
  ```bash
  netctl http 8000 -c example.com
  ```

- **List Active Connections:**  
  Display all current tunnels.
  ```bash
  netctl list
  ```

- **Stop a Specific Connection:**  
  Stop a tunnel using its connection ID.
  ```bash
  netctl stop <connection_id>
  ```

- **Stop All Connections:**  
  Shut down all active tunnels.
  ```bash
  netctl stopall
  ```

- **Display Help:**  
  Show the detailed help message.
  ```bash
  netctl help
  ```

## Dependencies 🛠️

NetCtl requires a few common utilities:

- [`jq`](https://stedolan.github.io/jq/) for JSON parsing
- [`sshpass`](https://linux.die.net/man/1/sshpass) for non-interactive SSH password handling
- [`curl`](https://curl.se/) for API requests
- [`ssh`](https://www.openssh.com/) (or `openssh-client`) for establishing tunnels

If any dependencies are missing, the script will automatically attempt to install them using your system's package manager.

## Contributing 🤝

Contributions, bug reports, and feature requests are very welcome! Feel free to fork the repository and open a pull request with your improvements.

## License 📄

This project is licensed under the [MIT License](LICENSE).

---

Happy tunneling! 🌐🚀

Feel free to modify this README to suit your project's needs.

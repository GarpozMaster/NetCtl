# NetCtl 🚀

NetCtl is an open-source, ready-to-run service that effortlessly exposes your localhost to the internet. Powered by SSH, it runs in the background and is fully controllable via simple commands—perfect for developers and remote access enthusiasts alike.

## Installation 📥

### 1. Using curl (or wget)

Download the NetCtl script directly to `/bin/netctl` and make it executable:

#### With curl

```bash
sudo curl -L https://raw.githubusercontent.com/GarpozMaster/NetCtl/main/NetCtl.sh -o /bin/NetCtl
sudo chmod +x /bin/NetCtl
```

#### With wget

```bash
sudo wget https://raw.githubusercontent.com/GarpozMaster/NetCtl/main/NetCtl.sh -O /bin/NetCtl
sudo chmod +x /bin/NetCtl
```

### 2. Using Git Clone

```bash
git clone https://github.com/GarpozMaster/NetCtl.git
cd NetCtl
sudo cp netctl.sh /bin/NetCtl
sudo chmod +x /bin/NetCtl
```

Now you can run `NetCtl` from anywhere on your system.

---

## Features ✨

* **Open Source & Ready to Use** 🔓
  Easily expose your localhost to the internet with a single command.
* **Custom Local Host Support** 🖧
  Choose which local interface to tunnel from, using `[host:]port` syntax.
* **SSH-Powered Tunneling** 🔀
  Secure tunnels over SSH that run quietly in the background.
* **Dynamic Connection Management** 🛑
  List, stop, and control active tunnels easily.
* **Automatic Dependency Handling** 🛠️
  Detects your OS and installs required packages automatically.
* **Shell Auto-Completion** ⌨️
  Get faster with built-in command completion.

---

## Usage 🚀

* **Save a Token**

  ```bash
  NetCtl token YOUR_API_TOKEN
  ```

* **Login via Browser**

  ```bash
  NetCtl login
  ```

* **Start a TCP Tunnel (default host `127.0.0.1`)**

  ```bash
  NetCtl tcp 8080
  ```

* **Start a TCP Tunnel from a Specific Local Host**
  Example: Tunnel a service running on LAN IP `192.168.1.1`

  ```bash
  NetCtl tcp 192.168.1.1:8080
  ```

* **Start an HTTP Tunnel**

  ```bash
  NetCtl http 8000
  ```

* **Start an HTTP Tunnel from a Specific Local Host**

  ```bash
  NetCtl http 192.168.1.1:8000
  ```

* **HTTP Tunnel with Custom Domain**

  ```bash
  NetCtl http 8000 -c example.com
  ```

* **List Active Connections**

  ```bash
  NetCtl list
  ```

* **Stop a Specific Connection**

  ```bash
  NetCtl stop <connection_id>
  ```

* **Stop All Connections**

  ```bash
  NetCtl stopall
  ```

* **Show Help**

  ```bash
  NetCtl help
  ```

---

## Dependencies 🛠️

NetCtl requires:

* [`jq`](https://stedolan.github.io/jq/) — JSON parsing
* [`sshpass`](https://linux.die.net/man/1/sshpass) — non-interactive SSH password handling
* [`curl`](https://curl.se/) — API communication
* [`ssh`](https://www.openssh.com/) / `openssh-client` — tunnel creation

If missing, NetCtl will auto-install them via your package manager.

---

## Contributing 🤝

Contributions, bug reports, and feature requests are welcome!
Fork the repo and open a pull request with your improvements.

Windows & Mac support coming soon! 🖥️🍏

---

## License 📄

This project is licensed under the [MIT License](LICENSE).

---

Happy tunneling! 🌐🚀

Made with ❤️ by Garpoz Master

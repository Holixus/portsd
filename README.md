
A simple TCP ports reply server for routers port-forwarding/DMZ testing.

## build

```sh
cmake .
make
```

## install

```sh
make install
```

## usage

```
Usage: socked <options> [ip:port[-port]]+

options:
  -i, --iface=<interface>    : bind listen socket to the network interace;
  -d, --daemon               : start as daemon;
  -f, --pid-file=<filename>  : set PID file name;
  -h                         : print this help and exit.
```

# Librarian Versions

## 0.1

- first implementation
- ssh commands
- scp features
- ssh library api
- use ssh configuration parameters from file

### 0.1.1

- support for identity files
- move the connection tag to the process dictionary instead of
  the message queue.

### 0.1.2

- smarter defaults for run! and send!

### 0.1.3

- correct error trapping on connect!

### 0.1.4

- correct error calculating sizes of iolists

### 0.1.5

- enable usage of tty: true in order to stream tty.
- ~~enable environment variables, but this blocks on [ERL-1107](https://bugs.erlang.org/browse/ERL-1107/)~~

### 0.1.6

- update documentation in confusing spots.

### 0.1.7

- add `:user_interaction` and `:save_accepted_host` values.
- disable user interaction as a default
- add `SSH.Key.gen/3` function.

### 0.1.8

- add `:link` option to link the calling process to the ssh connection.

### 0.1.9

- add support for new SSH module changes present in OTP 23

### 0.1.10

- fix typo that affects OTP < 23

### 0.1.11

- remove warning message on env variable error

### 0.1.12

- allow Enum.into to error out when nonzero return code function is run

### 0.2.0

- allow file and generic streaming into scp streams

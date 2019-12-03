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
- enable environment variables, but this blocks on [ERL-1107](https://bugs.erlang.org/browse/ERL-1107/)

### 0.1.6 (proposed)

- attempt streaming scp

## 0.2

(planned)

- process structure: tasks, servers

## 0.3

(planned)

- servers?

#!/usr/bin/python
import socket
import sys

HOST, PORT = "localhost", 54321
data = " ".join(sys.argv[1:])

# Create a socket (SOCK_STREAM means a TCP socket)
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

try:
    # Connect to server and send data
    sock.connect((HOST, PORT))
    sock.sendall(data + "\n")
    print "send data ", data, " to host", HOST, "and port", PORT

    # Receive data from the server and shut down
    received = sock.recv(1024)
    print "Sent:     {}".format(data)
    print "Received: {}".format(received)
    
except IOError:    
    print "Error : no connection - server down?"
    print "Host  :", HOST
    print "Port  :", PORT
    sys.exit(1)

finally:
    sock.close()
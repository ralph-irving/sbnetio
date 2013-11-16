#!/usr/bin/python

import asyncore
import socket
import select
import os

class Client(asyncore.dispatcher_with_send):
    def __init__(self, socket=None, pollster=None):
        asyncore.dispatcher_with_send.__init__(self, socket)
        self.data = ''
        self.unregistered = 0
        if pollster:
            self.pollster = pollster
            pollster.register(self, select.EPOLLIN)

    def handle_close(self):
         if self.unregistered == 0 :
             if self.pollster:
                self.pollster.unregister(self)
                self.unregistered = 1
                print "Connection closed"
 
    def handle_read(self):
        receivedData = self.recv(8192)

        if not receivedData:
            self.close()
            return
        receivedData = self.data + receivedData
        while '\n' in receivedData:
            line, receivedData = receivedData.split('\n',1)
            self.handle_command(line)
        self.data = receivedData

    def handle_command(self, line):
        server_reply = "red"

        client_data =  line
        client_words = client_data.split(' ')
        client_cmd   = client_words[0]

        print line

        if client_cmd == "Test":
            print "Test"
            server_reply = "green"
        elif client_cmd == "":
            server_reply = "No Cmd given!"
            print server_reply
        else:
            Dir = '/home/pi/netio/./'
            CmdName = Dir + client_cmd
 
            if os.access(CmdName, os.X_OK):
               Cmd = 'sudo ' + Dir + line
               os.popen(Cmd)
               server_reply = line
            else:
               server_reply = "Unknown Cmd: " + CmdName
               print server_reply
  
        self.send(server_reply)

class Server(asyncore.dispatcher):
    def __init__(self, listen_to, pollster):
        asyncore.dispatcher.__init__(self)
        self.pollster = pollster
        self.create_socket(socket.AF_INET, socket.SOCK_STREAM)
        self.bind(listen_to)
        self.listen(5)

    def handle_accept(self):
        newSocket, address = self.accept()
        print "Connected from", address
        Client(newSocket,self.pollster)

def readwrite(obj, flags):
    try:
        if flags & select.EPOLLIN:
            obj.handle_read_event()
        if flags & select.EPOLLOUT:
            obj.handle_write_event()
        if flags & select.EPOLLPRI:
            obj.handle_expt_event()
        if flags & (select.EPOLLHUP | select.EPOLLERR | select.POLLNVAL):
            obj.handle_close()
    except socket.error, e:
        if e.args[0] not in asyncore._DISCONNECTED:
            obj.handle_error()
        else:
            obj.handle_close()
    except asyncore._reraised_exceptions:
        raise
    except:
        obj.handle_error()

class EPoll(object):
    def __init__(self):
        self.epoll = select.epoll()
        self.fdmap = {}

    def register(self, obj, flags):
        fd = obj.fileno()
        self.epoll.register(fd, flags)
        self.fdmap[fd] = obj

    def unregister(self, obj):
        fd = obj.fileno()
        del self.fdmap[fd]
        self.epoll.unregister(fd)

    def poll(self):
        evt = self.epoll.poll()
        for fd, flags in evt:
            yield self.fdmap[fd], flags

if __name__ == "__main__":
        pollster = EPoll()
        pollster.register(Server(("",54321),pollster), select.EPOLLIN)
        while True:
            evt = pollster.poll()
            for obj, flags in evt:
                readwrite(obj, flags)


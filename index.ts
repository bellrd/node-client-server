import * as net from "net";
import Connection from "./connection";
import ConnectionQueue from "./queue";

let connectionQueue = new ConnectionQueue();

let server = net.createServer((socket) => {
  try {
    // new socket connected (created)
    let connection = new Connection(socket);
    connectionQueue.add(connection);
  } catch (e) {
    // connection can not be added into queue 
    // close the socket
    socket.write("sorry bro");
    socket.destroy();
  }
});

connectionQueue.eventEmitter.on("modified", () => {
  while (connectionQueue.length) {
    let c = connectionQueue.remove();
    c.socket.write("some string");
    c.socket.destroy();
    // setTimeout(() => c.socket.destroy(), 200);
  }
});

server.listen(8080, () => {
  console.log("server started");
});

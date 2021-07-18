import * as net from "net";
import ConnectionQueue from "./queue";


let connectionQueue = new ConnectionQueue();

let server = net.createServer((connection) => {
  try {
    connectionQueue.add(connection);
  } catch (e) {
    connection.write("connection full sorry !!");
    connection.destroy();
  }
});

connectionQueue.eventEmitter.on("modified", ()=> {
 while(connectionQueue.queue.length){
  let c = connectionQueue.remove();
  c.write("some string");
  c.destroy();
  setTimeout(() => c.destroy(), 200);
 }
});

server.listen(8080, () => {
 console.log("");
});

import * as net from "net";
import Connection from "./connection";
import ConnectionQueue from "./queue";
import Stack from "./stack";

let connectionQueue = new ConnectionQueue();
let stack = new Stack();

let server = net.createServer();

server.on("connection", (socket: net.Socket) => {
    // new socket opened; creating connection object
    let connection = new Connection(socket);
    try {
        // try to add to connection queue
        console.log("INFO", "Got new connection...", connectionQueue.length);
        connectionQueue.add(connection); // will raise added event
        // console.log(connectionQueue);
    } catch (e) {
        // connection can not be added into queue
        // so close the socket
        // busy state
        console.log("INFO", "Rejecting connection due to 100 limit exceed.", connectionQueue.length)
        connection.socket.write(Buffer.from([0xff]));
        // connection.socket.write(Buffer.alloc(1));
        connection.socket.destroy();
        // console.log(connectionQueue);
    }
});

connectionQueue.eventEmitter.on("added", () => {
    let c = connectionQueue.oldest();
    if (!c.data) return;
    let header = c.data[0];
    let msb = header & (1 << 7);
    if (msb) {
        try {
            console.log("popping from stack");
            let poppedItem = stack.pop();
            console.log(stack);

            poppedItem.size = poppedItem.size & ~(1<<7);
            let buffer1 = Buffer.from([poppedItem.size]);
            let buffer2 = poppedItem.buffer
            let result = Buffer.concat([buffer1, buffer2]);
            console.log("INFO: writing to connection");
            c.socket.write(result);
            console.log(result.toString());
            console.log("destroying connection due to already written");
            c.socket.destroy();
            // console.log(connectionQueue);
            connectionQueue.remove();
        } catch (e) {
            console.log(e);
            console.log("INFO: can not pop due to stack empty issue")
            console.log(stack);
            return;
        }
    } else {
        console.log("pushing");
        let size = header & ~(1 << 7);
        let buffer = c.data.slice(1);
        try {
            console.log("pushing: ", size, " ", buffer.toString());
            stack.push({size, buffer});
            console.log(stack);
            c.socket.write(Buffer.alloc(1).fill(0));
            c.socket.destroy();
            connectionQueue.remove();
        } catch (e) {
            console.log("can not push due to no space");
            console.log(stack);
            return;
        }
        // push request
    }
    // connectionQueue.remove();
    // }
});

server.listen(8080, () => {
    console.log("server started");
});

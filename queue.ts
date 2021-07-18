import * as events from "events";
import Connection from "./connection";

//change it to 100
const MAX_CONNECTION = 100;

class ConnectionQueue {
    queue: Connection[];
    eventEmitter = new events.EventEmitter();

    constructor() {
        this.queue = [];
    }

    // @ts-ignore
    get length() {
        return this.queue.length;
    }

    add(connection: Connection) {
        // if connection is full then try to remove
        // oldest one (if it is older than 10s),
        // if no older than throw some error
        if (this.queue.length === MAX_CONNECTION) {
            let oldestConnection = this.queue[0];
            if (oldestConnection.isOlderThan10s()) {
                // oldestConnection.socket.write(Buffer.from([0xff]));
                oldestConnection.socket.destroy();
                this.remove();
                console.log("removing connection ", this.queue.length , " - 1")
            } else throw Error("Queue full !!");
        }
        // connection can be added normally now
        console.log("adding connection", this.queue.length, " +1");
        connection.socket.on("data", (data) => {
            // console.log("data", data);
            connection.data = data;
            this.eventEmitter.emit("added");
        });
        this.queue.push(connection);
    }

    oldest(): Connection {
        if (this.queue.length === 0) throw Error("Queue empty");
        return this.queue[0];
    }

    remove(): Connection {
        // if queue is empty then throw some error
        if (this.queue.length === 0) throw Error("Queue empty");
        console.log("removing connection ", this.queue.length , " - 1")
        return this.queue.shift();
    }
}

export default ConnectionQueue;

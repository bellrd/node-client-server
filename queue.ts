import * as events from "events";
import Connection from "./connection";

//change it to 100
const MAX_CONNECTION = 2;
class ConnectionQueue {
  queue: Connection[];
  eventEmitter = new events.EventEmitter();

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
        oldestConnection.socket.write("very old one!! ");
        oldestConnection.socket.destroy();
      } else throw Error("Queue full !!");
    }
    // connection can be added normally now
    this.queue.push(connection);
    // this.eventEmitter.emit("modified");
  }

  remove(): Connection {
    // if queue is empty then throw some error
    if (this.queue.length === 0) throw Error("Queue empty");
    return this.queue.shift();
  }

  constructor() {
    this.queue = [];
  }
}

export default ConnectionQueue;

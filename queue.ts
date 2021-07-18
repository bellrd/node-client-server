import * as net from "net";
import * as events from "events";

class ConnectionQueue {

 queue:net.Socket[];
 eventEmitter = new events.EventEmitter();

 add(connection:net.Socket) {
  if(this.queue.length === 100){
   throw Error("Queue full");
  }
  this.queue.push(connection);
  // console.log(this.queue.length);
  this.eventEmitter.emit("modified");
 }


 remove():net.Socket {
  if(this.queue.length === 0) throw Error("Queue empty");
  return this.queue.shift();
 }

 constructor(){
  this.queue = [];
 }

}

export default ConnectionQueue;
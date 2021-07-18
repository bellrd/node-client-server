import * as net from "net";

class Connection {
  socket: net.Socket;
  connectTime: number;
  data: any;

  isOlderThan10s(): boolean {
    let now = Math.floor(Date.now() / 1000);
    return (now - this.connectTime) >= 2;
  }

  constructor(socket: net.Socket) {
    this.socket = socket;
    this.connectTime = Math.floor(Date.now() / 1000);
  }
}

export default Connection;

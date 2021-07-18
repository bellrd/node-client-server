const MAX_STACK_LIMIT = 100;

export type StackItem = {
  size: number;
  buffer: any;
};

class Stack {
  data: StackItem[] = [];

  push(stackItem: StackItem) {
    if (this.data.length === MAX_STACK_LIMIT) {
      throw Error("stack full");
    }
    return this.data.push(stackItem);
  }

  pop(): StackItem {
    if (this.data.length === 0) {
      throw Error("stack empty");
    }
    return this.data.pop();
  }
}

export default Stack;

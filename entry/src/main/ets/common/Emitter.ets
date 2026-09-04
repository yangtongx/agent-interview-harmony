export class Emitter {
  private listeners: Array<() => void> = [];

  subscribe(fn: () => void): () => void {
    this.listeners.push(fn);
    return (): void => {
      this.unsubscribe(fn);
    };
  }

  unsubscribe(fn: () => void): void {
    const next: Array<() => void> = [];
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] !== fn) {
        next.push(this.listeners[i]);
      }
    }
    this.listeners = next;
  }

  emit(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i]();
    }
  }
}

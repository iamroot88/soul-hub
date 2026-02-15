class WebSocketClient {
  private ws: WebSocket | null = null
  private url: string = 'ws://localhost:3001/ws'
  private reconnectAttempts = 0
  private maxReconnectAttempts = 5

  connect(): WebSocket {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      return this.ws
    }

    try {
      this.ws = new WebSocket(this.url)
      
      this.ws.addEventListener('open', () => {
        console.log('WebSocket connected')
        this.reconnectAttempts = 0
      })

      this.ws.addEventListener('error', (e) => {
        console.error('WebSocket error:', e)
      })

      this.ws.addEventListener('close', () => {
        console.log('WebSocket disconnected')
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
          this.reconnectAttempts++
          setTimeout(() => this.connect(), 2000 * this.reconnectAttempts)
        }
      })

      return this.ws
    } catch (err) {
      console.error('Failed to connect WebSocket:', err)
      return new EventTarget() as any
    }
  }

  disconnect() {
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
  }

  send(data: any) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data))
    }
  }
}

export default new WebSocketClient()

import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import SoulCards from './components/SoulCards'
import TraitChart from './components/TraitChart'
import WebSocketClient from './utils/websocket'

interface Soul {
  meta: {
    botId: string
    botName: string
    role: string
    lastUpdated: string
  }
  declared: {
    creature: string
    emoji: string
    traits: string[]
  }
  traits: {
    declared: string[]
  }
  vectors: Record<string, any>
}

function App() {
  const [souls, setSouls] = useState<Record<string, Soul>>({})
  const [selectedSoul, setSelectedSoul] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // Fetch initial data
    fetch('http://localhost:3000/api/souls')
      .then(res => res.json())
      .then(data => {
        setSouls(data.data)
        const firstSoulId = Object.keys(data.data)[0]
        setSelectedSoul(firstSoulId)
        setLoading(false)
      })
      .catch(err => {
        console.error('Failed to fetch souls:', err)
        setLoading(false)
      })

    // Setup WebSocket for live updates
    const ws = WebSocketClient.connect()
    
    const handleMessage = (message: any) => {
      if (message.type === 'update') {
        setSouls(message.data)
      }
    }

    ws.addEventListener('message', (e) => {
      const message = JSON.parse(e.data)
      handleMessage(message)
    })

    return () => {
      WebSocketClient.disconnect()
    }
  }, [])

  const currentSoul = selectedSoul ? souls[selectedSoul] : null

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-purple-900 p-8">
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.6 }}
        className="max-w-7xl mx-auto"
      >
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-5xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-purple-300 to-blue-300 mb-2">
            🧠 Soul Maps
          </h1>
          <p className="text-purple-200">Interactive trait visualization & soul analysis</p>
        </div>

        {/* Main Content */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Left: Soul Cards */}
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.6 }}
            className="lg:col-span-1"
          >
            <SoulCards
              souls={souls}
              selectedSoul={selectedSoul}
              onSelectSoul={setSelectedSoul}
            />
          </motion.div>

          {/* Right: Visualization */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.6 }}
            className="lg:col-span-2"
          >
            {loading ? (
              <div className="flex items-center justify-center h-96 backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20">
                <p className="text-white">Loading souls...</p>
              </div>
            ) : currentSoul ? (
              <TraitChart soul={currentSoul} />
            ) : (
              <div className="flex items-center justify-center h-96 backdrop-blur-xl bg-white/10 rounded-3xl border border-white/20">
                <p className="text-white">Select a soul to view</p>
              </div>
            )}
          </motion.div>
        </div>
      </motion.div>
    </div>
  )
}

export default App

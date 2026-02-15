import { motion } from 'framer-motion'

interface Soul {
  meta: {
    botId: string
    botName: string
    role: string
  }
  declared?: {
    emoji: string
    creature: string
  }
}

interface Props {
  souls: Record<string, Soul>
  selectedSoul: string | null
  onSelectSoul: (soulId: string) => void
}

export default function SoulCards({ souls, selectedSoul, onSelectSoul }: Props) {
  return (
    <div className="space-y-4">
      <h2 className="text-2xl font-bold text-white mb-6">Souls</h2>
      <div className="space-y-3 max-h-96 overflow-y-auto">
        {Object.entries(souls).map(([id, soul]) => (
          <motion.button
            key={id}
            onClick={() => onSelectSoul(id)}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            className={`w-full p-4 rounded-2xl backdrop-blur-xl transition-all text-left ${
              selectedSoul === id
                ? 'bg-white/20 border border-purple-300'
                : 'bg-white/5 border border-white/10 hover:bg-white/10'
            }`}
          >
            <div className="flex items-center gap-3">
              <span className="text-3xl">{soul.declared?.emoji || '🧬'}</span>
              <div className="flex-1">
                <div className="font-bold text-white">{soul.meta.botName}</div>
                <div className="text-sm text-purple-200">{soul.meta.role}</div>
              </div>
            </div>
          </motion.button>
        ))}
      </div>
    </div>
  )
}

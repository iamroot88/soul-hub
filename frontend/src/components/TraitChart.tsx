import { PolarAngleAxis, PolarGridAngleAxis, PolarRadiusAxis, Radar, RadarChart, ResponsiveContainer } from 'recharts'
import { motion } from 'framer-motion'

interface Soul {
  meta: {
    botName: string
  }
  declared: {
    emoji: string
    traits: string[]
  }
  vectors?: Record<string, any>
}

interface Props {
  soul: Soul
}

export default function TraitChart({ soul }: Props) {
  // Prepare radar data from traits
  const data = soul.declared.traits.map((trait, idx) => {
    const angle = (idx / soul.declared.traits.length) * Math.PI * 2
    const value = 60 + Math.random() * 40
    return {
      name: trait,
      value: Math.round(value),
      angle
    }
  })

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.5 }}
      className="glass p-8 rounded-3xl"
    >
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-white mb-2">
          {soul.declared.emoji} {soul.meta.botName}
        </h2>
        <p className="text-purple-200">Trait Radiance Map</p>
      </div>

      {data.length > 0 ? (
        <div className="h-96">
          <ResponsiveContainer width="100%" height="100%">
            <RadarChart data={data}>
              <PolarAngleAxis
                dataKey="name"
                tick={{ fill: '#e9d5ff', fontSize: 12 }}
              />
              <PolarRadiusAxis
                angle={90}
                domain={[0, 100]}
                tick={{ fill: '#c084fc', fontSize: 10 }}
              />
              <Radar
                name="Trait Strength"
                dataKey="value"
                stroke="#a855f7"
                fill="#a855f7"
                fillOpacity={0.4}
                animationDuration={800}
              />
            </RadarChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <div className="h-96 flex items-center justify-center">
          <p className="text-purple-200">No trait data available</p>
        </div>
      )}

      {/* Trait List */}
      <div className="mt-8 grid grid-cols-2 gap-3">
        {soul.declared.traits.map((trait, idx) => (
          <motion.div
            key={idx}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: idx * 0.05 }}
            className="glass-sm p-3 rounded-lg"
          >
            <p className="text-sm text-purple-200">{trait}</p>
          </motion.div>
        ))}
      </div>
    </motion.div>
  )
}

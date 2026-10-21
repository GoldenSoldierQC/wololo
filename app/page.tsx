import civs from '@/data/civs.json';
import maps from '@/data/maps.json';
import buildOrders from '@/data/build_orders.json';

export default function HomePage() {
  return (
    <main className="min-h-screen bg-neutral-950 text-neutral-100 p-8 font-mono">
      <header className="max-w-6xl mx-auto mb-8 border-b border-neutral-800 pb-4">
        <h1 className="text-2xl font-bold tracking-tight text-amber-400">
          WOLOLO DESK — STEP 1: DATA ONLY (res://data/)
        </h1>
        <p className="text-sm text-neutral-400 mt-1">
          Static JSON definitions for 8 original civilizations, 4 maps, and 8 build-order plan families with counter cycles.
        </p>
      </header>

      <div className="max-w-6xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-6">
        <section className="bg-neutral-900 border border-neutral-800 p-4 rounded">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-amber-300 mb-3">
            res://data/civs.json ({civs.length})
          </h2>
          <ul className="space-y-2 text-xs">
            {civs.map((c) => (
              <li key={c.id} className="border-b border-neutral-800/80 pb-2 last:border-none">
                <div className="flex justify-between font-bold text-neutral-100">
                  <span>{c.name}</span>
                  <span className="text-amber-400">{c.power_spike}</span>
                </div>
                <div className="text-neutral-400 mt-0.5">
                  id: <code className="text-neutral-300">{c.id}</code> · tags: {c.tags.join(', ')}
                </div>
              </li>
            ))}
          </ul>
        </section>

        <section className="bg-neutral-900 border border-neutral-800 p-4 rounded">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-emerald-300 mb-3">
            res://data/maps.json ({maps.length})
          </h2>
          <ul className="space-y-2 text-xs">
            {maps.map((m) => (
              <li key={m.id} className="border-b border-neutral-800/80 pb-2 last:border-none">
                <div className="flex justify-between font-bold text-neutral-100">
                  <span>{m.name}</span>
                  <span className="text-emerald-400">{m.kind}</span>
                </div>
                <div className="text-neutral-400 mt-0.5">
                  id: <code className="text-neutral-300">{m.id}</code> · favored: {m.favored_tags.join(', ')}
                </div>
              </li>
            ))}
          </ul>
        </section>

        <section className="bg-neutral-900 border border-neutral-800 p-4 rounded">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-sky-300 mb-3">
            res://data/build_orders.json ({buildOrders.length})
          </h2>
          <ul className="space-y-2 text-xs">
            {buildOrders.map((b) => (
              <li key={b.id} className="border-b border-neutral-800/80 pb-2 last:border-none">
                <div className="flex justify-between font-bold text-neutral-100">
                  <span>{b.name}</span>
                  <span className="text-sky-400">
                    {b.timing} · tax {b.execution_tax.toFixed(2)}
                  </span>
                </div>
                <div className="text-neutral-400 mt-0.5">
                  maps: {b.map_kinds.join(', ')}
                </div>
                <div className="text-emerald-400/90 mt-0.5">
                  beats: {b.beats.join(', ')}
                </div>
                <div className="text-rose-400/90 mt-0.5">
                  loses_to: {b.loses_to.join(', ')}
                </div>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </main>
  );
}

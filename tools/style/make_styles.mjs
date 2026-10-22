// Builds Arah's offline map styles from Protomaps basemaps.
// Output has placeholder source/glyph/sprite URLs that the app fills in.
import { layers, namedFlavor } from '@protomaps/basemaps';
import { writeFileSync, mkdirSync } from 'node:fs';
mkdirSync('../../assets/styles', { recursive: true });
for (const flavor of ['light', 'dark']) {
  const style = {
    version: 8,
    glyphs: '{GLYPHS}',
    sprite: '{SPRITE}/' + flavor,
    sources: { protomaps: { type: 'vector', url: '{PMTILES}', attribution: '© OpenStreetMap · Protomaps' } },
    layers: layers('protomaps', namedFlavor(flavor), { lang: 'en' }),
  };
  writeFileSync(`../../assets/styles/${flavor}.json`, JSON.stringify(style));
  const fonts = new Set();
  for (const l of style.layers) for (const f of (l.layout?.['text-font'] ?? [])) fonts.add(f);
  console.log(flavor, style.layers.length, 'layers; fonts:', [...fonts].join(', '));
}

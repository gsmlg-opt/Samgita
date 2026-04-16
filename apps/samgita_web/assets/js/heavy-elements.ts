// Heavy custom elements loaded as a separate bundle to isolate
// mermaid/d3 and code-engine/lezer from LiveView's main bundle.
// d3-selection's dispatchEvent function conflicts with LiveView when
// bundled together by bun.
import { register as registerMarkdown } from '@duskmoon-dev/el-markdown'
import { register as registerMarkdownInput } from '@duskmoon-dev/el-markdown-input'
import { register as registerCodeEngine } from '@duskmoon-dev/el-code-engine'

try { registerMarkdown() } catch (e) { console.warn('el-dm-markdown:', e) }
try { registerMarkdownInput() } catch (e) { console.warn('el-dm-markdown-input:', e) }
try { registerCodeEngine() } catch (e) { console.warn('el-dm-code-engine:', e) }

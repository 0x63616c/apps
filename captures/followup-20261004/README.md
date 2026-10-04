# October 4 regression evidence

Unedited native simulator framebuffer attachments from final `just verify`. PNG orientation metadata is preserved. Data is synthetic; the fixture never accesses personal Photos or writes an index.

- Four date handoffs sampled at fractional offsets in both directions, portrait/landscape, light/dark. Top header-band pixels remain opaque throughout all 320 controlled samples. Pictured **Back / Next** buttons are fixture-only controls, absent from production.
- Real LibraryStore refresh receives identical screenshot metadata every 500ms while indexing progresses without pause flashes. Manual pause/resume is verified separately.
- Final suite: 10 native, 28 portable core, and 15 release-tool tests pass; unsigned production Release compilation passes.

Source fixes are not yet in a new TestFlight build. These checks do not prove physical-device Photos/iCloud behavior, real-library speed, or OS background runtime.

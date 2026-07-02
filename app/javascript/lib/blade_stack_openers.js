// #529 (Hans, 2026-06-06): Entity-Öffner aus blade_stack_controller.js
// ausgelagert (Refactoring-Schritt 3). Die dünnen Action-Handler, die eine
// Entität (Liste/Source/Task/Topic/Awaiting/Communication) als Blade an den
// Stack hängen — alle delegieren an this._appendBladeAtUrl (bleibt im
// Controller, gemeinsame Engine). Wird als Mixin aufs Prototype gemixt,
// damit Stimulus die data-action-Handler über die Prototype-Chain findet und
// `this` weiterhin den Stack-Controller meint. Reines Code-Move, KEIN
// Verhalten geändert.
//
// Enthaltene Methoden (data-action `blade-stack#openX`):
//   openFromList · openSource · openTask · openTopic · openAwaiting · openCommunication

export const BladeStackOpenersMixin = {
  // #224 6f-2: Default-Klick auf ein Listen-Item ersetzt den nachge-
  // lagerten Sub-Stack (alles zwischen dieser List-Card und dem
  // naechsten list:*-Blade) durch die neue Card. Plus-Klick (separate
  // Action) wuerde stattdessen appenden.
  async openFromList(event) {
    event.preventDefault()
    const uuid = event.currentTarget.dataset.targetUuid
    if (!uuid) return
    const sourceListCard = event.target?.closest?.("article.stack-card[data-uuid^='list:']")
    const existing = this.cardForUuid(uuid)
    if (existing) {
      this._expandCard(existing)
      existing.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
      this.setActiveCard(existing)
      return
    }
    if (sourceListCard) {
      const url = this.cardUrlTemplateValue.replace("UUID", uuid)
      await this._appendBladeAtUrl({ stackId: uuid, url,
                                     sourceListCard, mode: "replace_substack" })
    } else {
      await this.appendCard(uuid)
    }
    this.pushTrailState()
    this.applyHighlighting()
    this.refreshTrailControls()
    this.syncUrl({ pushHistory: true })
  },

  // Klick auf einen Source-Cite-Link oder Source-Verweis: Source-Card
  // rechts am Stack anhängen statt das KI-Detail-Frame zu ersetzen
  // ("Content missing"-Symptom). Sources nehmen NICHT am Trail teil —
  // sie sind Beiwerk, nicht Navigations-Hauptweg.
  async openSource(event) {
    event.preventDefault()
    event.stopPropagation()
    const slug = event.currentTarget.dataset.sourceSlug
    if (!slug) return
    await this._appendBladeAtUrl({
      stackId: `src:${slug}`,
      url:     `/sources/${encodeURIComponent(slug)}/card`
    })
    this._autoCollapseSourceList(event)
  },

  // #163 Phase 2: Task als Blade im Stack anhaengen. Analog zu
  // openSource — Tasks nehmen ebenfalls NICHT am Trail teil (sie sind
  // Beiwerk in einer Wissens-Navigation). Erwartet event.currentTarget
  // mit data-task-id.
  async openTask(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.taskId
    if (!id) return
    await this._appendBladeAtUrl({
      stackId: `task:${id}`,
      url:     `/tasks/${encodeURIComponent(id)}/card`
    })
    this._autoCollapseSourceList(event)
  },

  // #163 Phase 4: Topic als Blade im Stack anhaengen. Analog zu
  // openTask/openSource. Erwartet event.currentTarget mit data-topic-slug.
  async openTopic(event) {
    event.preventDefault()
    event.stopPropagation()
    const slug = event.currentTarget.dataset.topicSlug
    if (!slug) return
    await this._appendBladeAtUrl({
      stackId: `topic:${slug}`,
      url:     `/topics/${encodeURIComponent(slug)}/card`
    })
    this._autoCollapseSourceList(event)
  },

  // #163 Phase 5b-1: Awaiting als Blade. data-awaiting-id.
  async openAwaiting(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.awaitingId
    if (!id) return
    await this._appendBladeAtUrl({
      stackId: `awaiting:${id}`,
      url:     `/awaitings/${encodeURIComponent(id)}/card`
    })
    this._autoCollapseSourceList(event)
  },

  // #533 #5: Aufgabe öffnen UND zur Zeiten-Subsection scrollen. data-task-id.
  async openTaskTimes(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.taskId
    if (!id) return
    await this._appendBladeAtUrl({ stackId: `task:${id}`, url: `/tasks/${encodeURIComponent(id)}/card` })
    requestAnimationFrame(() => {
      const card = this.cardForUuid(`task:${id}`)
      if (card) this.scrollToAnchorInCard(card, `task_times_${id}`)
    })
  },

  // #533 #5: Topic-Reiter-Blade direkt am Zeiten-Reiter öffnen. data-topic-slug.
  async openTopicTimes(event) {
    event.preventDefault()
    event.stopPropagation()
    const slug = event.currentTarget.dataset.topicSlug
    if (!slug) return
    await this._appendBladeAtUrl({
      stackId: `topic:${slug}:times`,
      url:     `/topics/${encodeURIComponent(slug)}/list_card?tab=times`
    })
  },

  // #533 #2b: Zeitbuchung als Detail-Blade. data-time-entry-id.
  async openTimeEntry(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.timeEntryId
    if (!id) return
    await this._appendBladeAtUrl({
      stackId: `time:${id}`,
      url:     `/time_entries/${encodeURIComponent(id)}/card`
    })
  },

  // #532: Dokument als Detail-Blade öffnen. data-document-id. Klick aus der
  // Liste ersetzt den Sub-Stack (wie openFromList), sonst Append.
  async openDocument(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.documentId
    if (!id) return
    const existing = this.cardForUuid(`document:${id}`)
    if (existing) {
      this._expandCard(existing)
      existing.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" })
      this.setActiveCard(existing)
      return
    }
    const sourceListCard = event.target?.closest?.("article.stack-card[data-uuid^='list:']")
    const opts = { stackId: `document:${id}`, url: `/documents/${encodeURIComponent(id)}/card` }
    if (sourceListCard) { opts.sourceListCard = sourceListCard; opts.mode = "replace_substack" }
    await this._appendBladeAtUrl(opts)
    this.syncUrl({ pushHistory: true })
  },

  // #163 Phase 5b-1: Communication als Blade. data-communication-id.
  async openCommunication(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.communicationId
    if (!id) return
    await this._appendBladeAtUrl({
      stackId: `communication:${id}`,
      url:     `/communications/${encodeURIComponent(id)}/card`
    })
    this._autoCollapseSourceList(event)
  }
}

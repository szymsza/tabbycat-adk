<template>
  <drag-and-drop-layout
    :unallocatedItems="unallocatedItems"
    :unallocatedComponent="unallocatedComponent"
    :handle-unused-drop="moveAdjudicator"
    :handle-panel-swap="swapPanels"
  >
    <drag-and-drop-actions
      slot="actions"
      :count="debatesOrPanelsCount"
      prioritise="true"
      allocate="true"
      shard="true"
      @show-shard="showShard"
      @show-allocate="showAllocate"
      @show-prioritise="showPrioritise"
    >
      <template slot="default-highlights">
        <button
          class="btn conflictable conflicts-toolbar hover-histories-2-ago"
          data-toggle="tooltip"
          v-text="gettext('Seen')"
          :title="'Has judged this team or with this adjudicator previously'"
        ></button>
        <button
          class="btn conflictable conflicts-toolbar hover-institution"
          data-toggle="tooltip"
          v-text="gettext('Institution')"
          :title="'Is from the same institution as this team or panelist.'"
        ></button>
        <button
          class="btn conflictable conflicts-toolbar hover-adjudicator"
          data-toggle="tooltip"
          v-text="gettext('Conflict')"
          :title="'Has a nominated conflict with this team or panelist.'"
        ></button>
        <button
          class="btn panel-incomplete"
          data-toggle="tooltip"
          v-text="gettext('Missing')"
          :title="'Panel is missing a chair or enough adjudicators for a voting majority.'"
        ></button>
      </template>
    </drag-and-drop-actions>

    <template slot="debates">
      <div v-for="(group, gi) in groupedDebatesByRound" :key="'r-' + group.round_seq" class="mb-4">
        <div v-if="groupedDebatesByRound.length > 1" class="mt-2 mb-3">
          <hr v-if="gi > 0" class="my-3" />
          <div class="text-muted small" v-text="group.round_name"></div>
        </div>
        <drag-and-drop-debate
          v-for="debate in group.debates"
          :key="debate.id"
          :debateOrPanel="debate"
          :maxTeams="maxTeams"
        >
          <debate-or-panel-importance
            slot="importance"
            :debate-or-panel="debate"
          ></debate-or-panel-importance>
          <debate-or-panel-adjudicators
            slot="adjudicators"
            :debate-or-panel="debate"
            :handle-debate-or-panel-drop="moveAdjudicator"
            :handle-panel-swap="swapPanels"
          >
          </debate-or-panel-adjudicators>
          <template slot="venue"><span></span></template
          ><!--Hide Venues-->
        </drag-and-drop-debate>
      </div>
      <div class="text-center lead mx-5 p-5" v-if="sortedDebatesOrPanels.length === 0">
        <p class="mx-5 lead mt-2 px-5" v-text="gettext(noDebatesInline)"></p>
      </div>
    </template>

    <template slot="modals">
      <modal-for-sharding :intro-text="gettext(intro)"></modal-for-sharding>
      <modal-for-allocating
        :intro-text="
          gettext(`Auto-allocate will remove adjudicators from all debates
        and create new panels in their place.`)
        "
        :context-of-action="'allocate_debate_adjs'"
      ></modal-for-allocating>
      <modal-for-prioritising
        :intro-text="gettext(prioritiseIntro)"
        :context-of-action="'prioritise_debates'"
      ></modal-for-prioritising>
    </template>
  </drag-and-drop-layout>
</template>

<script>
import EditEitherAdjudicatorsSharedMixin from './EditEitherAdjudicatorsSharedMixin.vue'

export default {
  mixins: [EditEitherAdjudicatorsSharedMixin],
  data: () => ({
    intro: `Sharding narrows the panels displayed to show only a specific subset of all
      panels available.`,
    prioritiseIntro: `Using auto-prioritise will remove all existing debate priorities and assign
      new ones.`,
    noDebatesInline: 'There are no debates created for this round.',
  }),
  computed: {
    maxTeams: function () {
      return Math.max(...this.sortedDebatesOrPanels.map(d => d.teams ? d.teams.length : 0), 2)
    },
    groupedDebatesByRound: function () {
      // Group already-sorted debates by their round for visual separation
      const groups = {}
      for (const d of this.sortedDebatesOrPanels) {
        const seq = d.round_seq ?? this.roundSlugForWSPath
        if (!Object.prototype.hasOwnProperty.call(groups, seq)) {
          groups[seq] = { round_seq: seq, round_name: d.round_name, debates: [] }
        }
        groups[seq].debates.push(d)
      }
      // Return in ascending round order
      return Object.values(groups).sort((a, b) => Number(a.round_seq) - Number(b.round_seq))
    },
  },
}
</script>

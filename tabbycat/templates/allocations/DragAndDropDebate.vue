<template>
  <div class="d-flex border-bottom bg-white">
    <slot name="bracket" v-if="!isElimination">
      <div v-if="debateOrPanel.bracket >= 0" class="flex-1-25 flex-truncate d-flex border-right"
           data-toggle="tooltip" :title="gettext(`The debate's bracket`)">
        <div class="align-self-center flex-fill text-center" v-text="debateOrPanel.bracket"></div>
      </div>
      <div v-else class="flex-2 flex-truncate d-flex border-right"
           data-toggle="tooltip" :title="gettext(`The bracket range of the hypothetical debate`)">
        <div class="align-self-center flex-fill text-center">
          <span v-if="debateOrPanel.bracket_min !== debateOrPanel.bracket_max">
            {{ debateOrPanel.bracket_min }}<span class="text-muted">-</span>{{ debateOrPanel.bracket_max }}
          </span>
          <span v-else>{{ debateOrPanel.bracket_min }}</span>
        </div>
      </div>
    </slot>
    <slot name="rank" v-if="isElimination">
      <div v-if="debateOrPanel.bracket >= 0" class="flex-1-25 flex-truncate d-flex border-right"
           data-toggle="tooltip" :title="gettext(`The debate's room rank (break rank of highest-ranked team)`)">
        <div class="align-self-center flex-fill text-center" v-text="debateOrPanel.room_rank"></div>
      </div>
    </slot>
    <slot name="liveness" v-if="!isElimination">
      <div v-if="debateOrPanel.bracket >= 0" class="flex-1-25 flex-truncate border-right d-flex"
           data-toggle="tooltip" :title="gettext(`The total number of live break categories across
              all teams`)">
        <div class="align-self-center flex-fill text-center" v-text="liveness">
        </div>
      </div>
      <div v-else class="flex-1-25 flex-truncate border-right d-flex"
           data-toggle="tooltip" :title="gettext(`The maximum possible number of live teams in
              the hypothetical debate for the open category`)">
        <div class="align-self-center flex-fill text-center" v-text="liveness"></div>
      </div>
    </slot>
    <slot name="importance">
      <div class="flex-1-25 flex-truncate border-right d-flex"
           data-toggle="tooltip" :title="gettext(`This debate's priority`)">
        <div class="align-self-center flex-fill text-center">{{ debateOrPanel.importance }}</div>
      </div>
    </slot>
    <slot name="venue">
      <div class="flex-6 flex-truncate border-right align-self-center p-2 small">
        <span v-if="debateOrPanel.venue">{{ debateOrPanel.venue.display_name }}</span>
      </div>
    </slot>
    <slot name="teams">
      <div class="teams-list" :style="{ flex: (maxTeams + maxTeams % 2) * 3, 'flex-direction': 'row !important', 'flex-wrap': 'wrap' }" v-if="debateOrPanel.teams">
        <div :class="['d-flex flex-fill flex-truncate align-items-center']" v-for="team in debateOrPanel.teams" :key="team ? team.id : 'empty-' + $index">
          <inline-team :debate-id="debateOrPanel.id" :is-elimination="isElimination" :team="team" :key="team.id" v-if="team !== null"/>
        </div>
      </div>
    </slot>
    <slot name="adjudicators">
      <div class="flex-16 align-self-center p-2 small d-flex flex-wrap">
        <inline-adjudicator v-for="adj in debateOrPanel.adjudicators.C"
                             :key="'C-' + adj.id" :adjudicator="adj"
                             :debate-id="debateOrPanel.id" role="C" />
        <inline-adjudicator v-for="adj in debateOrPanel.adjudicators.P"
                             :key="'P-' + adj.id" :adjudicator="adj"
                             :debate-id="debateOrPanel.id" role="P" />
        <inline-adjudicator v-for="adj in debateOrPanel.adjudicators.T"
                             :key="'T-' + adj.id" :adjudicator="adj"
                             :debate-id="debateOrPanel.id" role="T" />
      </div>
    </slot>
  </div>
</template>

<script>
// Provides the base template for a debate object used across all edit adjudicator screens
// Uses slots so that parent components can override them with custom components for editing the
// specific type of data they are responsible for
import { mapState } from 'vuex'
import InlineTeam from '../../draw/templates/InlineTeam.vue'
import InlineAdjudicator from '../../adjallocation/templates/InlineAdjudicator.vue'

export default {
  components: { InlineTeam, InlineAdjudicator },
  props: ['debateOrPanel', 'maxTeams'],
  computed: {
    sides: function () {
      return this.$store.state.tournament.sides
    },
    isElimination: function () {
      return this.round.stage === 'E'
    },
    liveness: function () {
      if ('liveness' in this.debateOrPanel) {
        // For preformed panel screens liveness is attached to the panel itself
        return this.debateOrPanel.liveness
      } else {
        // For allocation screens, it's a property of the teams that is then summed
        let liveness = 0
        if ('teams' in this.debateOrPanel && this.debateOrPanel.teams) {
          for (const keyAndEntry of Object.entries(this.debateOrPanel.teams)) {
            const team = keyAndEntry[1]
            // Team can be a number (ID) or null (e.g. when editing sides)
            if (team !== null && typeof team === 'object' && 'break_categories' in team) {
              for (const bc of team.break_categories) {
                const category = this.highlights.break.options[bc]
                if (category && team.points > category.fields.dead && team.points < category.fields.safe) {
                  liveness += 1
                }
              }
            }
          }
        }
        return liveness
      }
    },
    ...mapState(['highlights', 'round']),
  },
}
</script>

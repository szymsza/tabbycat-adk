from django.test import TestCase

from adjallocation.models import DebateAdjudicator
from draw.models import Debate, DebateTeam
from draw.types import DebateSide
from participants.models import Adjudicator, Team
from results.forms import PerAdjudicatorBallotSetForm, SingleBallotSetForm
from results.models import BallotSubmission
from tournaments.models import Round, Tournament


class PerAdjudicatorBallotSetFormTests(TestCase):

    def setUp(self):
        self.tournament = Tournament.objects.create(slug="formtest", name="Form Test")
        round = Round.objects.create(
            tournament=self.tournament, seq=1, abbreviation="R1",
        )
        self.debate = Debate.objects.create(round=round)
        for side in (DebateSide.AFF, DebateSide.NEG):
            team = Team.objects.create(tournament=self.tournament, reference=f"Team {side}")
            DebateTeam.objects.create(debate=self.debate, team=team, side=side)

        self.adjudicator = Adjudicator.objects.create(
            tournament=self.tournament, name="Chair", base_score=5,
        )
        DebateAdjudicator.objects.create(
            debate=self.debate,
            adjudicator=self.adjudicator,
            type=DebateAdjudicator.TYPE_CHAIR,
        )
        self.ballotsub = BallotSubmission(debate=self.debate)

    def enable_self_split_ballots(self):
        self.tournament.preferences['debate_rules__ballots_per_debate_prelim'] = 'per-adj'
        self.tournament.preferences['data_entry__allow_self_split_ballots'] = True

    def test_self_split_field_shown_for_solo_adjudicator(self):
        self.enable_self_split_ballots()

        form = PerAdjudicatorBallotSetForm(self.ballotsub, tabroom=True)

        self.assertIn(form._fieldname_self_split(), form.fields)

    def test_self_split_field_shown_on_solo_individual_ballot(self):
        self.enable_self_split_ballots()
        self.ballotsub.single_adj = True

        form = SingleBallotSetForm(self.ballotsub, tabroom=False)

        self.assertIn(form._fieldname_self_split(), form.fields)

    def test_self_split_field_hidden_for_panel_individual_ballot(self):
        self.enable_self_split_ballots()
        self.ballotsub.single_adj = True
        panellist = Adjudicator.objects.create(
            tournament=self.tournament, name="Panellist", base_score=5,
        )
        DebateAdjudicator.objects.create(
            debate=self.debate,
            adjudicator=panellist,
            type=DebateAdjudicator.TYPE_PANEL,
        )

        form = SingleBallotSetForm(self.ballotsub, tabroom=False)

        self.assertNotIn(form._fieldname_self_split(), form.fields)

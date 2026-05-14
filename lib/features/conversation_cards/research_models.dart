final class ResearchBudgetEstimate {
  const ResearchBudgetEstimate({
    required this.topic,
    required this.pagesLabel,
    required this.tokensLabel,
    required this.costLabel,
    required this.scopeSummary,
  });

  final String topic;
  final String pagesLabel;
  final String tokensLabel;
  final String costLabel;
  final String scopeSummary;

  static ResearchBudgetEstimate demo() {
    return const ResearchBudgetEstimate(
      topic: 'School policy change brief',
      pagesLabel: '42 pages',
      tokensLabel: '36k tokens',
      costLabel: r'$2.40 estimated',
      scopeSummary: 'Search official notices and summarize policy changes.',
    );
  }
}

final class ResearchResult {
  const ResearchResult({
    required this.title,
    required this.brief,
    required this.keyPoints,
    required this.sources,
    required this.draftNote,
  });

  final String title;
  final String brief;
  final List<String> keyPoints;
  final List<ResearchCitation> sources;
  final String draftNote;

  static ResearchResult demo() {
    return const ResearchResult(
      title: 'Policy memo outline',
      brief: 'A concise brief is ready with cited sources and a reusable note.',
      keyPoints: [
        'The source set is bounded to official documentation.',
        'The draft note keeps citations separate from conclusions.',
      ],
      sources: [
        ResearchCitation(
          number: 1,
          title: 'OpenAI Docs',
          domain: 'openai.com',
          fetchedLabel: 'May 13, 2026 09:20',
        ),
      ],
      draftNote: 'Use this outline as a note after reviewing the citations.',
    );
  }
}

final class ResearchCitation {
  const ResearchCitation({
    required this.number,
    required this.title,
    required this.domain,
    required this.fetchedLabel,
  });

  final int number;
  final String title;
  final String domain;
  final String fetchedLabel;
}

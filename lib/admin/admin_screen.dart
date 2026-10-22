import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand/avatar.dart';
import '../brand/badges.dart';
import '../core/data.dart';
import '../core/inbox.dart';
import '../core/models.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../home/new_chat.dart';
import '../ui/kit.dart';
import '../core/i18n.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.preview});

  final Map<String, dynamic>? preview;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<String> get _tabs => [tr('Stats'), tr('News'), 'Finn', tr('Safety'), tr('Badges')];
  final _pages = PageController();
  int _tab = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int i) {
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
    _pages.animateToPage(i, duration: const Duration(milliseconds: 460), curve: kSmooth);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: const TopBar(title: 'Admin'),
      body: Column(children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Reveal(
                  delay: Duration(milliseconds: 40 * i),
                  child: GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: kSmooth,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _tab == i ? p.ink : p.soft, borderRadius: BorderRadius.circular(17)),
                      child: Text(_tabs[i], style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tab == i ? p.paper : p.ink)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _tab = i),
            children: [
              _StatsTab(preview: widget.preview),
              const _NewsTab(),
              const _FinnTab(),
              const _SafetyTab(),
              const _BadgesTab(),
            ],
          ),
        ),
      ]),
    );
  }
}

class _StatsTab extends StatefulWidget {
  const _StatsTab({this.preview});
  final Map<String, dynamic>? preview;

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _stats;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stats = widget.preview;
    if (_stats == null) _load();
  }

  Future<void> _load() async {
    try {
      final s = await supa.rpc('admin_stats');
      if (mounted) setState(() => _stats = (s as Map).cast<String, dynamic>());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = Palette.of(context);
    final s = _stats;
    if (s == null) return Center(child: _failed ? Text(tr('Could not load stats'), style: TextStyle(color: p.muted)) : const Spinner());
    final items = [
      (tr('People'), s['users'], Icons.people_alt_outlined),
      (tr('Active today'), s['active_today'], Icons.bolt_rounded),
      (tr('Chats'), s['chats'], Icons.forum_outlined),
      (tr('Messages'), s['messages'], Icons.chat_bubble_outline_rounded),
      (tr('Messages today'), s['messages_today'], Icons.today_outlined),
    ];
    return RefreshIndicator(
      color: p.ink,
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.25),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return Reveal(
            delay: Duration(milliseconds: 60 * i),
            scale: 0.85,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: i == 0 ? p.ink : p.card, borderRadius: BorderRadius.circular(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(it.$3, color: i == 0 ? p.paper : p.ink, size: 22),
                const Spacer(),
                CountUp(
                  value: (it.$2 as num?) ?? 0,
                  style: TextStyle(fontFamily: kDisplayFont, fontSize: 34, fontWeight: FontWeight.w800, color: i == 0 ? p.paper : p.ink, letterSpacing: -1),
                ),
                Text(it.$1, style: TextStyle(fontSize: 13.5, color: i == 0 ? p.paper.withValues(alpha: 0.7) : p.muted)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _NewsTab extends StatefulWidget {
  const _NewsTab();

  @override
  State<_NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<_NewsTab> with AutomaticKeepAliveClientMixin {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Inbox.instance.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Inbox.instance.removeListener(_changed);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() => _busy = true);
    try {
      await supa.from('announcements').insert({'title': _title.text.trim(), 'body': _body.text.trim()});
      _title.clear();
      _body.clear();
      await Inbox.instance.loadAnnouncements();
      if (mounted) showToast(context, tr('Posted to everyone'));
    } catch (_) {
      if (mounted) showToast(context, tr('Could not post.'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(Announcement a) async {
    final ok = await confirm(context, title: tr('Delete this post?'), body: a.title, action: tr('Delete'), danger: true);
    if (!ok) return;
    try {
      await supa.from('announcements').delete().eq('id', a.id);
      await Inbox.instance.loadAnnouncements();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = Palette.of(context);
    final items = Inbox.instance.announcements;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Reveal(child: FishiField(controller: _title, label: tr('Title'), maxLength: 80, onChanged: (_) => setState(() {}))),
        const SizedBox(height: 10),
        Reveal(
          delay: const Duration(milliseconds: 50),
          child: FishiField(controller: _body, label: tr('What is new?'), maxLines: 6, maxLength: 4000, textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
        ),
        const SizedBox(height: 14),
        Reveal(
          delay: const Duration(milliseconds: 100),
          child: PillButton(
            label: tr('Post announcement'),
            icon: Icons.campaign_outlined,
            busy: _busy,
            onTap: _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty ? _post : null,
          ),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < items.length; i++)
          Reveal(
            key: ValueKey(items[i].id),
            delay: Duration(milliseconds: 140 + 40 * i),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(items[i].title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.ink)),
                    const SizedBox(height: 3),
                    Text(items[i].body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.muted)),
                    const SizedBox(height: 4),
                    Text(dayHeader(items[i].createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
                  ]),
                ),
                CircleIcon(icon: Icons.delete_outline_rounded, size: 34, onTap: () => _delete(items[i])),
              ]),
            ),
          ),
      ],
    );
  }
}

const _googleEndpoint = 'https://generativelanguage.googleapis.com/v1beta/openai';
const _openRouterEndpoint = 'https://openrouter.ai/api/v1';
const _defaultModels = ['gemini-3.8-flash', 'gemini-3.7-flash', 'gemini-3.6-flash', 'gemini-3.5-flash'];

String _providerName(String endpoint) {
  if (endpoint.contains('googleapis')) return 'Google AI';
  if (endpoint.contains('openrouter')) return 'OpenRouter';
  return Uri.tryParse(endpoint)?.host ?? endpoint;
}

class _FinnTab extends StatefulWidget {
  const _FinnTab();

  @override
  State<_FinnTab> createState() => _FinnTabState();
}

class _FinnTabState extends State<_FinnTab> with AutomaticKeepAliveClientMixin {
  final _prompt = TextEditingController();
  final _newModel = TextEditingController();
  List<Map<String, dynamic>> _keys = [];
  List<String> _models = [];
  bool _loaded = false;
  bool _failed = false;
  bool _modelsDirty = false;
  bool _savingModels = false;
  bool _savingPrompt = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _newModel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = (await supa.rpc('admin_get_finn_config') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _keys = ((c['keys'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
        _models = ((c['models'] as List?) ?? const []).cast<String>();
        _prompt.text = c['system_prompt'] as String? ?? '';
        _modelsDirty = false;
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = _loaded = true);
    }
  }

  Future<void> _editKey([Map<String, dynamic>? key]) async {
    final saved = await Navigator.of(context).push<bool>(sheetRoute(_KeySheet(existing: key)));
    if (saved == true) {
      await _load();
      if (mounted) showToast(context, tr('Finn updated'));
    }
  }

  Future<void> _removeKey(Map<String, dynamic> key) async {
    final ok = await confirm(context, title: tr('Remove {name}?', {'name': key['label']}), body: tr('Finn will stop using this key.'), action: tr('Remove'), danger: true);
    if (!ok) return;
    try {
      await supa.rpc('admin_remove_finn_key', params: {'key_id': key['id']});
      await _load();
    } catch (_) {
      if (mounted) showToast(context, tr('Could not save.'), error: true);
    }
  }

  Future<void> _moveKey(int i, int dir) async {
    final j = i + dir;
    if (j < 0 || j >= _keys.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      final k = _keys.removeAt(i);
      _keys.insert(j, k);
    });
    try {
      await supa.rpc('admin_order_finn_keys', params: {'key_ids': _keys.map((k) => k['id']).toList()});
    } catch (_) {
      if (mounted) showToast(context, tr('Could not save.'), error: true);
      await _load();
    }
  }

  void _moveModel(int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= _models.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      final m = _models.removeAt(i);
      _models.insert(j, m);
      _modelsDirty = true;
    });
  }

  void _addModel() {
    final m = _newModel.text.trim();
    if (m.isEmpty || _models.contains(m)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _models = [..._models, m];
      _modelsDirty = true;
    });
    _newModel.clear();
  }

  Future<void> _saveModels() async {
    if (_models.isEmpty) {
      showToast(context, tr('Add at least one model.'), error: true);
      return;
    }
    setState(() => _savingModels = true);
    try {
      await supa.rpc('admin_set_finn_models', params: {'new_models': _models});
      await _load();
      if (mounted) showToast(context, tr('Finn updated'));
    } catch (_) {
      if (mounted) showToast(context, tr('Could not save.'), error: true);
    }
    if (mounted) setState(() => _savingModels = false);
  }

  Future<void> _savePrompt() async {
    setState(() => _savingPrompt = true);
    try {
      await supa.rpc('admin_set_finn_config', params: {'new_system_prompt': _prompt.text});
      if (mounted) showToast(context, tr('Finn updated'));
    } catch (_) {
      if (mounted) showToast(context, tr('Could not save.'), error: true);
    }
    if (mounted) setState(() => _savingPrompt = false);
  }

  Widget _heading(String title, String body) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontFamily: kDisplayFont, fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
        const SizedBox(height: 4),
        Text(body, style: TextStyle(fontSize: 13, color: p.muted, height: 1.35)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = Palette.of(context);
    if (!_loaded) return const Center(child: Spinner());
    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Could not load Finn settings.'), style: TextStyle(color: p.muted)),
          const SizedBox(height: 12),
          SizedBox(width: 180, child: PillButton(label: tr('Try again'), secondary: true, onTap: () {
            setState(() => _loaded = false);
            _load();
          })),
        ]),
      );
    }
    final ready = _keys.isNotEmpty && _models.isNotEmpty;
    return RefreshIndicator(
      color: p.ink,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Reveal(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                const FinnAvatar(size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Finn', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.ink)),
                    Text(
                      ready
                          ? tr('{keys} keys, {models} models in the fallback chain', {'keys': _keys.length, 'models': _models.length})
                          : tr('No API key. Finn will say he is busy.'),
                      style: TextStyle(fontSize: 13.5, color: ready ? p.muted : p.danger),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          _heading(tr('API keys'), tr('Finn uses the first key. If it is rejected or out of quota, he moves to the next one.')),
          for (var i = 0; i < _keys.length; i++)
            Reveal(
              key: ValueKey(_keys[i]['id']),
              delay: Duration(milliseconds: 40 * i),
              child: _KeyCard(
                data: _keys[i],
                index: i,
                first: i == 0,
                last: i == _keys.length - 1,
                onEdit: () => _editKey(_keys[i]),
                onRemove: () => _removeKey(_keys[i]),
                onUp: () => _moveKey(i, -1),
                onDown: () => _moveKey(i, 1),
              ),
            ),
          const SizedBox(height: 4),
          PillButton(label: tr('Add a key'), icon: Icons.add_rounded, secondary: true, onTap: () => _editKey()),
          _heading(tr('Model fallback'), tr('For every key, Finn tries these models top to bottom until one answers.')),
          Container(
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              for (var i = 0; i < _models.length; i++) ...[
                if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 52, color: p.line),
                Padding(
                  key: ValueKey('m${_models[i]}'),
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: i == 0 ? p.ink : p.soft, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: i == 0 ? p.paper : p.ink)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_models[i], style: TextStyle(fontSize: 14.5, color: p.ink, fontFamily: kMonoFont))),
                    _SmallIcon(icon: Icons.keyboard_arrow_up_rounded, onTap: i == 0 ? null : () => _moveModel(i, -1)),
                    _SmallIcon(icon: Icons.keyboard_arrow_down_rounded, onTap: i == _models.length - 1 ? null : () => _moveModel(i, 1)),
                    _SmallIcon(
                      icon: Icons.close_rounded,
                      onTap: () => setState(() {
                        _models = [..._models]..removeAt(i);
                        _modelsDirty = true;
                      }),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: FishiField(controller: _newModel, label: tr('Add a model'), onSubmitted: (_) => _addModel())),
            const SizedBox(width: 8),
            CircleIcon(icon: Icons.add_rounded, size: 46, filled: true, onTap: _addModel),
          ]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _models = [..._defaultModels];
                _modelsDirty = true;
              }),
              child: Text(tr('Use Gemini 3.8 to 3.5'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: kSmooth,
            child: _modelsDirty
                ? Padding(padding: const EdgeInsets.only(top: 4), child: PillButton(label: tr('Save model order'), busy: _savingModels, onTap: _saveModels))
                : const SizedBox(width: double.infinity),
          ),
          _heading(tr('Extra system prompt'), tr('People never see these settings. Changes apply to the next Finn reply.')),
          FishiField(controller: _prompt, label: tr('Extra system prompt'), maxLines: 8),
          const SizedBox(height: 12),
          PillButton(label: tr('Save prompt'), busy: _savingPrompt, onTap: _savePrompt),
        ],
      ),
    );
  }
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tappable(
      scale: 0.8,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 22, color: onTap == null ? p.line : p.ink),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.data,
    required this.index,
    required this.first,
    required this.last,
    required this.onEdit,
    required this.onRemove,
    required this.onUp,
    required this.onDown,
  });

  final Map<String, dynamic> data;
  final int index;
  final bool first;
  final bool last;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final endpoint = data['endpoint'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: first ? p.ink : Colors.transparent, width: 1.5),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: first ? p.ink : p.soft, borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.key_rounded, size: 19, color: first ? p.paper : p.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data['label'] as String? ?? '', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 2),
            Text('${_providerName(endpoint)}  ·  ${data['hint'] ?? ''}', style: TextStyle(fontSize: 12.5, color: p.muted, fontFamily: kMonoFont)),
            if (first)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Used first'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.ink)),
              ),
          ]),
        ),
        _SmallIcon(icon: Icons.keyboard_arrow_up_rounded, onTap: first ? null : onUp),
        _SmallIcon(icon: Icons.keyboard_arrow_down_rounded, onTap: last ? null : onDown),
        _SmallIcon(icon: Icons.edit_outlined, onTap: onEdit),
        _SmallIcon(icon: Icons.delete_outline_rounded, onTap: onRemove),
      ]),
    );
  }
}

class _KeySheet extends StatefulWidget {
  const _KeySheet({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  late final _label = TextEditingController(text: widget.existing?['label'] as String? ?? '');
  late final _endpoint = TextEditingController(text: widget.existing?['endpoint'] as String? ?? _googleEndpoint);
  final _key = TextEditingController();
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _label.dispose();
    _endpoint.dispose();
    _key.dispose();
    super.dispose();
  }

  void _preset(String endpoint, String label) {
    HapticFeedback.selectionClick();
    setState(() {
      _endpoint.text = endpoint;
      if (_label.text.trim().isEmpty || _label.text == 'Google AI' || _label.text == 'OpenRouter') _label.text = label;
    });
  }

  Future<void> _save() async {
    if (!_editing && (_key.text.trim().isEmpty || _endpoint.text.trim().isEmpty)) {
      showToast(context, tr('Paste the key first.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await supa.rpc('admin_save_finn_key', params: {
        'key_id': widget.existing?['id'],
        'key_label': _label.text.trim(),
        'key_endpoint': _endpoint.text.trim(),
        'key_value': _key.text.trim().isEmpty ? null : _key.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, tr('Could not save.'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget chip(String label, String endpoint) {
      final on = _endpoint.text.trim() == endpoint;
      return Expanded(
        child: Tappable(
          scale: 0.95,
          onTap: () => _preset(endpoint, label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: kSmooth,
            height: 42,
            margin: const EdgeInsets.only(right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? p.ink : p.soft, borderRadius: BorderRadius.circular(14)),
            child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? p.paper : p.ink)),
          ),
        ),
      );
    }

    return BottomSheetFrame(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_editing ? tr('Edit key') : tr('Add a key'), style: TextStyle(fontFamily: kDisplayFont, fontSize: 22, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 14),
          Row(children: [chip('Google AI', _googleEndpoint), chip('OpenRouter', _openRouterEndpoint)]),
          const SizedBox(height: 12),
          FishiField(controller: _label, label: tr('Name'), maxLength: 40),
          const SizedBox(height: 10),
          FishiField(controller: _endpoint, label: tr('Endpoint'), keyboardType: TextInputType.url, onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          FishiField(controller: _key, label: _editing ? tr('New key (leave empty to keep)') : tr('API key'), obscure: true),
          const SizedBox(height: 18),
          PillButton(label: tr('Save'), busy: _busy, onTap: _save),
        ]),
      ),
    );
  }
}

class _SafetyTab extends StatefulWidget {
  const _SafetyTab();

  @override
  State<_SafetyTab> createState() => _SafetyTabState();
}

class _SafetyTabState extends State<_SafetyTab> with AutomaticKeepAliveClientMixin {
  final _term = TextEditingController();
  List<String> _terms = [];
  List<Map<String, dynamic>> _flags = [];
  bool _loaded = false;
  bool _open = true;
  bool _dirty = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _term.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await supa.rpc('admin_watch_terms');
      final f = await supa.rpc('admin_flags', params: {'only_open': _open});
      if (!mounted) return;
      setState(() {
        _terms = ((t as List?) ?? const []).cast<String>();
        _flags = ((f as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _add() {
    final t = _term.text.trim().toLowerCase();
    if (t.length < 2 || _terms.contains(t)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _terms = [..._terms, t]..sort();
      _dirty = true;
    });
    _term.clear();
  }

  Future<void> _saveTerms() async {
    try {
      await supa.rpc('admin_set_watch_terms', params: {'terms': _terms});
      setState(() => _dirty = false);
      if (mounted) showToast(context, tr('Watch list saved'));
    } catch (_) {
      if (mounted) showToast(context, tr('Could not save.'), error: true);
    }
  }

  Future<void> _review(Map<String, dynamic> f) async {
    try {
      await supa.rpc('admin_review_flag', params: {'flag_id': f['id']});
      setState(() => _flags = _flags.where((x) => x['id'] != f['id']).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = Palette.of(context);
    if (!_loaded) return const Center(child: Spinner());
    return RefreshIndicator(
      color: p.ink,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Reveal(
            child: Text(tr('Watch list'), style: TextStyle(fontFamily: kDisplayFont, fontSize: 20, fontWeight: FontWeight.w800, color: p.ink)),
          ),
          const SizedBox(height: 4),
          Text(tr('Only messages with these words or phrases get flagged. Ordinary swearing is never flagged. Under-18 age answers are flagged automatically.'),
              style: TextStyle(fontSize: 13, color: p.muted, height: 1.35)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FishiField(controller: _term, label: tr('Add a term'), onSubmitted: (_) => _add())),
            const SizedBox(width: 8),
            CircleIcon(icon: Icons.add_rounded, size: 46, filled: true, onTap: _add),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _terms)
              Reveal(
                key: ValueKey(t),
                scale: 0.6,
                offset: Offset.zero,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _terms = _terms.where((x) => x != t).toList();
                    _dirty = true;
                  }),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                    decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(t, style: TextStyle(fontSize: 14, color: p.ink, fontFamily: kMonoFont)),
                      const SizedBox(width: 4),
                      Icon(Icons.close_rounded, size: 15, color: p.muted),
                    ]),
                  ),
                ),
              ),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: kSmooth,
            child: _dirty
                ? Padding(padding: const EdgeInsets.only(top: 14), child: PillButton(label: tr('Save watch list'), onTap: _saveTerms))
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: Text(tr('Flagged'), style: TextStyle(fontFamily: kDisplayFont, fontSize: 20, fontWeight: FontWeight.w800, color: p.ink))),
            SizedBox(
              width: 170,
              child: Segmented<bool>(
                values: const [true, false],
                labels: [tr('Open'), tr('All')],
                value: _open,
                onChanged: (v) {
                  setState(() => _open = v);
                  _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_flags.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(child: Text(tr('Nothing flagged'), style: TextStyle(color: p.muted))),
            ),
          for (var i = 0; i < _flags.length; i++)
            Reveal(
              key: ValueKey(_flags[i]['id']),
              delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
              child: _FlagCard(flag: _flags[i], onReviewed: () => _review(_flags[i])),
            ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.flag, required this.onReviewed});

  final Map<String, dynamic> flag;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ctx = ((flag['context'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final open = flag['status'] == 'open';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(flag['matched'] as String? ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.danger)),
          ),
          const Spacer(),
          Text(dayHeader(DateTime.tryParse(flag['created_at'] as String? ?? '') ?? DateTime.now()), style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
        const SizedBox(height: 10),
        for (final m in ctx)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: m['flagged'] == true ? p.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: RichText(
              text: TextSpan(style: TextStyle(fontSize: 14, color: m['flagged'] == true ? p.paper : p.ink, fontFamily: kTextFont), children: [
                TextSpan(text: '@${m['username']}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: (m['kind'] == 'text' ? m['body'] : '[${m['kind']}]') as String? ?? ''),
              ]),
            ),
          ),
        if (open) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Tappable(
              onTap: onReviewed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(14)),
                child: Text(tr('Mark reviewed'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _BadgesTab extends StatefulWidget {
  const _BadgesTab();

  @override
  State<_BadgesTab> createState() => _BadgesTabState();
}

class _BadgesTabState extends State<_BadgesTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  List<Profile> _results = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String v) async {
    try {
      final r = await PeopleSearch.find(v);
      if (mounted) setState(() => _results = r);
    } catch (_) {}
  }

  Future<void> _toggle(Profile pr, String badge) async {
    final next = pr.badges.contains(badge) ? pr.badges.where((b) => b != badge).toList() : [...pr.badges, badge];
    try {
      await supa.rpc('admin_set_badges', params: {'target': pr.id, 'new_badges': next});
      await Profiles.instance.refresh(pr.id);
      final fresh = Profiles.instance[pr.id];
      if (fresh != null && mounted) setState(() => _results = _results.map((x) => x.id == pr.id ? fresh : x).toList());
    } catch (_) {
      if (mounted) showToast(context, tr('Could not change badges.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Reveal(child: FishiField(controller: _q, label: tr('Find someone'), prefix: '@', onChanged: _search)),
        const SizedBox(height: 12),
        for (final pr in _results)
          Reveal(
            key: ValueKey(pr.id),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(profile: pr, size: 38),
                  const SizedBox(width: 10),
                  Expanded(child: NameLine(name: pr.displayName, badges: pr.badges, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.ink))),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final b in const ['verified', 'staff', 'official'])
                    GestureDetector(
                      onTap: () => _toggle(pr, b),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: pr.badges.contains(b) ? p.ink : p.soft, borderRadius: BorderRadius.circular(14)),
                        child: Text(b, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pr.badges.contains(b) ? p.paper : p.ink)),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}

import { LightningElement, wire, track } from 'lwc';
import getSummaryMetrics from '@salesforce/apex/DashboardController.getSummaryMetrics';
import getMarkets       from '@salesforce/apex/DashboardController.getMarkets';
import getSites         from '@salesforce/apex/DashboardController.getSites';
import getCompetitors   from '@salesforce/apex/DashboardController.getCompetitors';
import getFinancials    from '@salesforce/apex/DashboardController.getFinancials';
import getScores        from '@salesforce/apex/DashboardController.getScores';
import chatApex         from '@salesforce/apex/AgentChatController.chat';

// ── Column definitions ────────────────────────────────────────────────────────

const MARKET_COLUMNS = [
    { label: 'City',        fieldName: 'City__c',           type: 'text',   initialWidth: 120 },
    { label: 'State',       fieldName: 'State__c',          type: 'text',   initialWidth: 100 },
    { label: 'Region',      fieldName: 'Region__c',         type: 'text',   initialWidth: 90  },
    { label: 'TAM (₹Cr)',   fieldName: 'tamCrore',          type: 'number', initialWidth: 100,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Growth %',    fieldName: 'Growth_Rate__c',    type: 'number', initialWidth: 90,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Competitors', fieldName: 'Competitor_Count__c', type: 'number', initialWidth: 110 },
    { label: 'Confidence',  fieldName: 'Confidence__c',     type: 'text',   initialWidth: 100 },
];

const SITE_COLUMNS = [
    { label: 'Site Name',     fieldName: 'Name',                type: 'text',    initialWidth: 180 },
    { label: 'City',          fieldName: 'City__c',             type: 'text',    initialWidth: 100 },
    { label: 'Demand Score',  fieldName: 'Demand_Score__c',     type: 'number',  initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Competition',   fieldName: 'Competition_Level__c',type: 'text',    initialWidth: 100 },
    { label: 'Rev/mo (₹L)',  fieldName: 'revLakh',             type: 'number',  initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Payback (mo)', fieldName: 'Payback_Period_Months__c', type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Recommended',  fieldName: 'Recommended__c',      type: 'boolean', initialWidth: 110 },
    { label: 'Status',       fieldName: 'Status__c',           type: 'text',    initialWidth: 100 },
];

const COMPETITOR_COLUMNS = [
    { label: 'Brand',      fieldName: 'Brand__c',          type: 'text',   initialWidth: 130 },
    { label: 'City',       fieldName: 'City__c',           type: 'text',   initialWidth: 100 },
    { label: 'State',      fieldName: 'State__c',          type: 'text',   initialWidth: 90  },
    { label: 'Format',     fieldName: 'Store_Format__c',   type: 'text',   initialWidth: 110 },
    { label: 'Rating',     fieldName: 'Rating__c',         type: 'number', initialWidth: 80,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Distance km',fieldName: 'Distance_km__c',    type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Size (sqft)',fieldName: 'Store_Size_Sqft__c',type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
];

const FINANCIAL_COLUMNS = [
    { label: 'Site',              fieldName: 'siteName',          type: 'text',   initialWidth: 180 },
    { label: 'City',              fieldName: 'city',              type: 'text',   initialWidth: 100 },
    { label: 'Setup (₹Cr)',       fieldName: 'setupCostCrore',    type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Rev/mo (₹L)',       fieldName: 'monthlyRevLakh',    type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Profit/mo (₹L)',   fieldName: 'monthlyProfitLakh', type: 'number', initialWidth: 120,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Payback (mo)',      fieldName: 'paybackMonths',     type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Annual ROI %',      fieldName: 'annualRoiPct',      type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 } },
    { label: 'Confidence',        fieldName: 'confidence',        type: 'text',   initialWidth: 100 },
];

const SCORE_COLUMNS = [
    { label: 'Site',          fieldName: 'siteName',           type: 'text',   initialWidth: 180 },
    { label: 'City',          fieldName: 'city',               type: 'text',   initialWidth: 100 },
    { label: 'Total Score',   fieldName: 'totalScore',         type: 'number', initialWidth: 100,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 },
      cellAttributes: { class: { fieldName: 'scoreClass' } } },
    { label: 'Demand',        fieldName: 'demandFactor',       type: 'number', initialWidth: 80,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Demographics',  fieldName: 'demographicsFactor', type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Competition',   fieldName: 'competitionFactor',  type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Accessibility', fieldName: 'accessFactor',       type: 'number', initialWidth: 110,
      typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
    { label: 'Scored By',     fieldName: 'scoredBy',           type: 'text',   initialWidth: 160 },
];

export default class StoreExpansionDashboard extends LightningElement {

    // ── Tab state ─────────────────────────────────────────────────────────────
    activeTab = 'overview';

    get showOverview()    { return this.activeTab === 'overview'; }
    get showMarkets()     { return this.activeTab === 'markets'; }
    get showSites()       { return this.activeTab === 'sites'; }
    get showCompetitors() { return this.activeTab === 'competitors'; }
    get showFinancials()  { return this.activeTab === 'financials'; }
    get showScores()      { return this.activeTab === 'scores'; }

    get overviewTabClass()     { return this.activeTab === 'overview'     ? 'tab-btn tab-active' : 'tab-btn'; }
    get marketsTabClass()      { return this.activeTab === 'markets'      ? 'tab-btn tab-active' : 'tab-btn'; }
    get sitesTabClass()        { return this.activeTab === 'sites'        ? 'tab-btn tab-active' : 'tab-btn'; }
    get competitorsTabClass()  { return this.activeTab === 'competitors'  ? 'tab-btn tab-active' : 'tab-btn'; }
    get financialsTabClass()   { return this.activeTab === 'financials'   ? 'tab-btn tab-active' : 'tab-btn'; }
    get scoresTabClass()       { return this.activeTab === 'scores'       ? 'tab-btn tab-active' : 'tab-btn'; }

    switchTab(evt) {
        this.activeTab = evt.target.dataset.tab;
    }

    // ── Column definitions ────────────────────────────────────────────────────
    marketColumns     = MARKET_COLUMNS;
    siteColumns       = SITE_COLUMNS;
    competitorColumns = COMPETITOR_COLUMNS;
    financialColumns  = FINANCIAL_COLUMNS;
    scoreColumns      = SCORE_COLUMNS;

    // ── Wire: Metrics ─────────────────────────────────────────────────────────
    @track metrics;

    @wire(getSummaryMetrics)
    wiredMetrics({ data, error }) {
        if (data)  this.metrics = data;
        if (error) console.error('metrics error', error);
    }

    // ── Wire: Markets ─────────────────────────────────────────────────────────
    _rawMarkets = [];

    @wire(getMarkets)
    wiredMarkets({ data, error }) {
        if (data) {
            this._rawMarkets = data.map(r => ({
                ...r,
                tamCrore: r.TAM__c ? parseFloat((r.TAM__c / 10000000).toFixed(0)) : null,
            }));
        }
        if (error) console.error('markets error', error);
    }

    get marketsForTable() { return this._rawMarkets; }

    // ── Wire: Sites ───────────────────────────────────────────────────────────
    _rawSites = [];

    @wire(getSites)
    wiredSites({ data, error }) {
        if (data) {
            this._rawSites = data.map(r => ({
                ...r,
                revLakh: r.Est_Monthly_Revenue__c ? parseFloat((r.Est_Monthly_Revenue__c / 100000).toFixed(1)) : null,
            }));
        }
        if (error) console.error('sites error', error);
    }

    get sitesForTable() { return this._rawSites; }

    // ── Wire: Competitors ─────────────────────────────────────────────────────
    @track competitors = [];

    @wire(getCompetitors)
    wiredCompetitors({ data, error }) {
        if (data)  this.competitors = data;
        if (error) console.error('competitors error', error);
    }

    // ── Wire: Financials ──────────────────────────────────────────────────────
    @track financials = [];

    @wire(getFinancials)
    wiredFinancials({ data, error }) {
        if (data)  this.financials = data;
        if (error) console.error('financials error', error);
    }

    // ── Wire: Scores ──────────────────────────────────────────────────────────
    @track scores = [];

    @wire(getScores)
    wiredScores({ data, error }) {
        if (data)  this.scores = data;
        if (error) console.error('scores error', error);
    }

    // ── Chat state ────────────────────────────────────────────────────────────
    @track chatHistory = [];
    @track userInput = '';
    @track isLoading = false;
    _msgCounter = 0;
    _agentSessionId = '';

    get hasChatHistory() { return this.chatHistory.length > 0; }

    handleInputChange(evt) {
        this.userInput = evt.target.value;
    }

    handleKeyDown(evt) {
        // Ctrl+Enter or Cmd+Enter to send
        if ((evt.ctrlKey || evt.metaKey) && evt.key === 'Enter') {
            evt.preventDefault();
            this.sendMessage();
        }
    }

    handleSend() {
        this.sendMessage();
    }

    handleQuick(evt) {
        this.userInput = evt.target.dataset.msg;
        const ta = this.template.querySelector('.chat-textarea');
        if (ta) { ta.value = this.userInput; }
        this.sendMessage();
    }

    sendMessage() {
        const text = (this.userInput || '').trim();
        if (!text || this.isLoading) return;

        // Add user message
        this._addMessage(text, 'user');
        this.userInput = '';
        // Clear textarea imperatively (no value binding on native textarea)
        const ta = this.template.querySelector('.chat-textarea');
        if (ta) { ta.value = ''; }
        this.isLoading = true;

        chatApex({ message: text, sessionId: this._agentSessionId })
            .then(response => {
                // response is JSON: { reply: '...', sessionId: '...' }
                try {
                    const parsed = JSON.parse(response);
                    if (parsed.sessionId) { this._agentSessionId = parsed.sessionId; }
                    this._addMessage(parsed.reply || response, 'agent');
                } catch (e) {
                    this._addMessage(response, 'agent');
                }
            })
            .catch(err => {
                const msg = err?.body?.message || err?.message || 'Unexpected error.';
                this._addMessage('⚠️ Error: ' + msg, 'agent');
            })
            .finally(() => {
                this.isLoading = false;
                this._scrollToBottom();
            });
    }

    _addMessage(text, sender) {
        const id = ++this._msgCounter;
        const now = new Date();
        const time = now.getHours().toString().padStart(2,'0') + ':' + now.getMinutes().toString().padStart(2,'0');
        this.chatHistory = [
            ...this.chatHistory,
            {
                id,
                text,
                time,
                rowClass:    sender === 'user' ? 'msg-row msg-user'  : 'msg-row msg-agent',
                bubbleClass: sender === 'user' ? 'msg-bubble user-bubble' : 'msg-bubble agent-bubble',
            }
        ];
        this._scrollToBottom();
    }

    _scrollToBottom() {
        // Defer to next tick so DOM is updated
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const box = this.refs.chatBox;
            if (box) box.scrollTop = box.scrollHeight;
        }, 50);
    }
}
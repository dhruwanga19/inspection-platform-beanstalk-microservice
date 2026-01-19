// services/frontend/src/App.jsx
import { useState, useEffect } from 'react';
import { api } from './services/api';
import { Home, ClipboardList, FileText, Upload, Plus, ArrowLeft, Check, X } from 'lucide-react';

export default function App() {
  const [view, setView] = useState('list');
  const [inspections, setInspections] = useState([]);
  const [selectedInspection, setSelectedInspection] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [notification, setNotification] = useState(null);

  useEffect(() => { loadInspections(); }, []);

  const loadInspections = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await api.listInspections();
      setInspections(data.inspections || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const showNotification = (message, type = 'success') => {
    setNotification({ message, type });
    setTimeout(() => setNotification(null), 3000);
  };

  const handleCreateInspection = async (data) => {
    try {
      await api.createInspection(data);
      showNotification('Inspection created successfully!');
      await loadInspections();
      setView('list');
    } catch (err) {
      showNotification(err.message, 'error');
    }
  };

  const handleUpdateInspection = async (id, updates) => {
    try {
      const result = await api.updateInspection(id, updates);
      setSelectedInspection(result.inspection);
      showNotification('Inspection updated!');
      await loadInspections();
    } catch (err) {
      showNotification(err.message, 'error');
    }
  };

  const handleGenerateReport = async (id) => {
    try {
      await api.generateReport(id);
      showNotification('Report generated! Notifications sent.');
      await loadInspections();
      const updated = await api.getInspection(id);
      setSelectedInspection(updated.inspection);
    } catch (err) {
      showNotification(err.message, 'error');
    }
  };

  const openInspection = async (id) => {
    try {
      setLoading(true);
      const data = await api.getInspection(id);
      setSelectedInspection(data.inspection);
      setView('detail');
    } catch (err) {
      showNotification(err.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {notification && (
        <div className={`fixed top-4 right-4 p-4 rounded-lg shadow-lg z-50 text-white ${notification.type === 'success' ? 'bg-green-500' : 'bg-red-500'}`}>
          {notification.message}
        </div>
      )}
      
      <header className="bg-blue-600 text-white p-4 shadow-lg">
        <div className="max-w-6xl mx-auto flex items-center justify-between">
          <h1 className="text-xl font-bold flex items-center gap-2">
            <ClipboardList size={24} />
            Building Inspection Platform
            <span className="text-xs bg-blue-500 px-2 py-1 rounded ml-2">Beanstalk</span>
          </h1>
          <button onClick={() => { setView('list'); setSelectedInspection(null); loadInspections(); }} className="flex items-center gap-1 hover:underline">
            <Home size={18} /> Dashboard
          </button>
        </div>
      </header>

      <main className="max-w-6xl mx-auto p-6">
        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
            <strong>Error:</strong> {error}
            <button onClick={loadInspections} className="ml-4 underline">Retry</button>
          </div>
        )}

        {loading && view === 'list' ? (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-4 border-blue-500 border-t-transparent"></div>
            <p className="mt-2 text-gray-600">Loading inspections...</p>
          </div>
        ) : (
          <>
            {view === 'list' && <InspectionList inspections={inspections} onSelect={openInspection} onCreate={() => setView('create')} />}
            {view === 'create' && <CreateInspection onSubmit={handleCreateInspection} onCancel={() => setView('list')} />}
            {view === 'detail' && selectedInspection && <InspectionDetail inspection={selectedInspection} onBack={() => { setView('list'); setSelectedInspection(null); }} onUpdate={handleUpdateInspection} onGenerateReport={handleGenerateReport} />}
          </>
        )}
      </main>
    </div>
  );
}

function InspectionList({ inspections, onSelect, onCreate }) {
  const statusColors = { DRAFT: 'bg-yellow-100 text-yellow-800', SUBMITTED: 'bg-blue-100 text-blue-800', REPORT_GENERATED: 'bg-green-100 text-green-800' };

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-2xl font-semibold">Inspections</h2>
        <button onClick={onCreate} className="bg-blue-600 text-white px-4 py-2 rounded-lg flex items-center gap-2 hover:bg-blue-700">
          <Plus size={18} /> New Inspection
        </button>
      </div>
      
      {inspections.length === 0 ? (
        <div className="text-center py-12 bg-white rounded-lg shadow"><p className="text-gray-500">No inspections yet. Create your first one!</p></div>
      ) : (
        <div className="grid gap-4">
          {inspections.map(insp => (
            <div key={insp.inspectionId} onClick={() => onSelect(insp.inspectionId)} className="bg-white p-4 rounded-lg shadow border hover:shadow-md cursor-pointer">
              <div className="flex justify-between items-start">
                <div>
                  <h3 className="font-semibold text-lg">{insp.propertyAddress}</h3>
                  <p className="text-gray-600 text-sm">Inspector: {insp.inspectorName}</p>
                  <p className="text-gray-500 text-sm">Created: {new Date(insp.createdAt).toLocaleDateString()}</p>
                </div>
                <span className={`px-3 py-1 rounded-full text-sm ${statusColors[insp.status] || 'bg-gray-100'}`}>{insp.status?.replace('_', ' ') || 'UNKNOWN'}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function CreateInspection({ onSubmit, onCancel }) {
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ propertyAddress: '', inspectorName: '', inspectorEmail: '', clientName: '', clientEmail: '' });

  const handleSubmit = async () => {
    if (!form.propertyAddress || !form.inspectorName || !form.inspectorEmail) { alert('Please fill required fields'); return; }
    setLoading(true);
    await onSubmit(form);
    setLoading(false);
  };

  return (
    <div className="max-w-2xl mx-auto">
      <button onClick={onCancel} className="flex items-center gap-1 text-gray-600 mb-4 hover:text-gray-800"><ArrowLeft size={18} /> Back</button>
      <h2 className="text-2xl font-semibold mb-6">Create New Inspection</h2>
      <div className="bg-white p-6 rounded-lg shadow space-y-4">
        <div><label className="block text-sm font-medium mb-1">Property Address *</label><input type="text" value={form.propertyAddress} onChange={e => setForm({...form, propertyAddress: e.target.value})} className="w-full p-2 border rounded" placeholder="123 Main St, City, State" /></div>
        <div className="grid grid-cols-2 gap-4">
          <div><label className="block text-sm font-medium mb-1">Inspector Name *</label><input type="text" value={form.inspectorName} onChange={e => setForm({...form, inspectorName: e.target.value})} className="w-full p-2 border rounded" /></div>
          <div><label className="block text-sm font-medium mb-1">Inspector Email *</label><input type="email" value={form.inspectorEmail} onChange={e => setForm({...form, inspectorEmail: e.target.value})} className="w-full p-2 border rounded" /></div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div><label className="block text-sm font-medium mb-1">Client Name</label><input type="text" value={form.clientName} onChange={e => setForm({...form, clientName: e.target.value})} className="w-full p-2 border rounded" /></div>
          <div><label className="block text-sm font-medium mb-1">Client Email</label><input type="email" value={form.clientEmail} onChange={e => setForm({...form, clientEmail: e.target.value})} className="w-full p-2 border rounded" /></div>
        </div>
        <div className="flex gap-3 pt-4">
          <button onClick={handleSubmit} disabled={loading} className="bg-blue-600 text-white px-6 py-2 rounded hover:bg-blue-700 disabled:opacity-50">{loading ? 'Creating...' : 'Create Inspection'}</button>
          <button onClick={onCancel} className="px-6 py-2 border rounded hover:bg-gray-50">Cancel</button>
        </div>
      </div>
    </div>
  );
}

function InspectionDetail({ inspection, onBack, onUpdate, onGenerateReport }) {
  const [checklist, setChecklist] = useState(inspection.checklist || {});
  const [notes, setNotes] = useState(inspection.notes || '');
  const [images, setImages] = useState(inspection.images || []);
  const [saving, setSaving] = useState(false);

  const options = ['Good', 'Fair', 'Poor'];
  const checklistItems = [{ key: 'roof', label: 'Roof Condition' }, { key: 'foundation', label: 'Foundation' }, { key: 'plumbing', label: 'Plumbing' }, { key: 'electrical', label: 'Electrical' }, { key: 'hvac', label: 'HVAC System' }];

  const handleImageUpload = async (e) => {
    for (const file of Array.from(e.target.files)) {
      try {
        const imageData = await api.uploadImage(inspection.inspectionId, file);
        setImages(prev => [...prev, imageData]);
      } catch (err) { console.error('Image upload failed:', err); }
    }
  };

  const handleSave = async () => { setSaving(true); await onUpdate(inspection.inspectionId, { checklist, notes, images, status: 'SUBMITTED' }); setSaving(false); };
  const handleGenerateReport = async () => { setSaving(true); await onGenerateReport(inspection.inspectionId); setSaving(false); };
  const canGenerateReport = Object.values(checklist).every(v => v !== null);

  if (inspection.status === 'REPORT_GENERATED') {
    return (<div><button onClick={onBack} className="flex items-center gap-1 text-gray-600 mb-4 hover:text-gray-800"><ArrowLeft size={18} /> Back to List</button><ReportView inspection={inspection} /></div>);
  }

  return (
    <div>
      <button onClick={onBack} className="flex items-center gap-1 text-gray-600 mb-4 hover:text-gray-800"><ArrowLeft size={18} /> Back to List</button>
      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <div className="flex justify-between items-start">
          <div><h2 className="text-2xl font-semibold">{inspection.propertyAddress}</h2><p className="text-gray-600">Inspector: {inspection.inspectorName} ({inspection.inspectorEmail})</p>{inspection.clientName && <p className="text-gray-600">Client: {inspection.clientName}</p>}</div>
          <span className="px-3 py-1 rounded-full text-sm bg-yellow-100 text-yellow-800">{inspection.status?.replace('_', ' ')}</span>
        </div>
      </div>

      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h3 className="text-lg font-semibold mb-4 flex items-center gap-2"><ClipboardList size={20} /> Inspection Checklist</h3>
        <div className="space-y-4">
          {checklistItems.map(item => (
            <div key={item.key} className="flex items-center justify-between py-2 border-b">
              <span className="font-medium">{item.label}</span>
              <div className="flex gap-2">
                {options.map(opt => (<button key={opt} onClick={() => setChecklist({...checklist, [item.key]: opt})} className={`px-4 py-1 rounded ${checklist[item.key] === opt ? opt === 'Good' ? 'bg-green-500 text-white' : opt === 'Fair' ? 'bg-yellow-500 text-white' : 'bg-red-500 text-white' : 'bg-gray-100 hover:bg-gray-200'}`}>{opt}</button>))}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h3 className="text-lg font-semibold mb-4 flex items-center gap-2"><Upload size={20} /> Property Images</h3>
        <input type="file" multiple accept="image/*" onChange={handleImageUpload} className="mb-4" />
        {images.length > 0 && (<div className="grid grid-cols-3 gap-4">{images.map(img => (<div key={img.imageId} className="bg-gray-100 p-3 rounded"><div className="bg-gray-300 h-24 rounded mb-2 flex items-center justify-center text-gray-500">📷</div><p className="text-sm truncate">{img.description}</p></div>))}</div>)}
      </div>

      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h3 className="text-lg font-semibold mb-4 flex items-center gap-2"><FileText size={20} /> Notes</h3>
        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={4} className="w-full p-3 border rounded" placeholder="Add inspection notes..." />
      </div>

      <div className="flex gap-4">
        <button onClick={handleSave} disabled={saving} className="bg-blue-600 text-white px-6 py-2 rounded hover:bg-blue-700 disabled:opacity-50">{saving ? 'Saving...' : 'Save Inspection'}</button>
        <button onClick={handleGenerateReport} disabled={!canGenerateReport || saving} className={`px-6 py-2 rounded flex items-center gap-2 ${canGenerateReport ? 'bg-green-600 text-white hover:bg-green-700' : 'bg-gray-300 text-gray-500 cursor-not-allowed'}`}><FileText size={18} /> Generate Report</button>
      </div>
    </div>
  );
}

function ReportView({ inspection }) {
  const getIcon = (val) => val === 'Good' ? <Check className="text-green-500" size={18} /> : val === 'Poor' ? <X className="text-red-500" size={18} /> : <span className="text-yellow-500">⚠️</span>;

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="border-b pb-4 mb-4">
        <h3 className="text-xl font-bold flex items-center gap-2"><FileText /> Inspection Report</h3>
        <p className="text-gray-500">Generated: {inspection.reportGeneratedAt ? new Date(inspection.reportGeneratedAt).toLocaleString() : 'N/A'}</p>
      </div>
      <div className="grid grid-cols-2 gap-6 mb-6">
        <div><h4 className="font-semibold mb-2">Property</h4><p>{inspection.propertyAddress}</p></div>
        <div><h4 className="font-semibold mb-2">Inspector</h4><p>{inspection.inspectorName}</p><p className="text-gray-600">{inspection.inspectorEmail}</p></div>
      </div>
      <div className="mb-6">
        <h4 className="font-semibold mb-3">Checklist Summary</h4>
        <div className="grid grid-cols-2 gap-3">
          {Object.entries(inspection.checklist || {}).map(([key, val]) => (<div key={key} className="flex items-center justify-between bg-gray-50 p-3 rounded"><span className="capitalize">{key}</span><span className="flex items-center gap-1">{getIcon(val)} {val}</span></div>))}
        </div>
      </div>
      {inspection.notes && (<div className="mb-6"><h4 className="font-semibold mb-2">Notes</h4><p className="bg-gray-50 p-3 rounded">{inspection.notes}</p></div>)}
      {inspection.images?.length > 0 && (<div><h4 className="font-semibold mb-2">Images ({inspection.images.length})</h4><div className="grid grid-cols-4 gap-2">{inspection.images.map(img => (<div key={img.imageId} className="bg-gray-200 h-20 rounded flex items-center justify-center text-gray-500 text-sm">📷 {img.description || 'Image'}</div>))}</div></div>)}
    </div>
  );
}
#pragma once
#include "camera.h"
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

struct ModelDocument {
    uint64_t id;
    std::string path;
    Camera camera;
};

// The starter is intentionally outside the document list. GPU resources live
// in the application; tab selection and per-document views need no GL context.
class Workspace {
public:
    const std::vector<ModelDocument>& documents() const { return m_documents; }
    ModelDocument* active() {
        for (auto& document : m_documents)
            if (document.id == m_active) return &document;
        return nullptr;
    }
    uint64_t find(const std::string& path) const {
        for (const auto& document : m_documents)
            if (document.path == path) return document.id;
        return 0;
    }
    uint64_t open(const std::string& path) {
        if (const auto existing = find(path)) { select(existing); return existing; }
        m_documents.push_back({m_next++, path, Camera{}});
        return m_active = m_documents.back().id;
    }
    void select(uint64_t id) {
        for (const auto& document : m_documents)
            if (document.id == id) { m_active = id; return; }
    }
    void cycle(int direction) {
        if (m_documents.empty()) return;
        auto current = std::find_if(m_documents.begin(), m_documents.end(),
            [&](const auto& document) { return document.id == m_active; });
        const auto count = static_cast<int>(m_documents.size());
        const auto index = static_cast<int>(current - m_documents.begin());
        m_active = m_documents[(index + direction % count + count) % count].id;
    }
    bool close(uint64_t id) {
        auto found = std::find_if(m_documents.begin(), m_documents.end(),
            [&](const auto& document) { return document.id == id; });
        if (found == m_documents.end()) return false;
        const auto index = static_cast<size_t>(found - m_documents.begin());
        const bool wasActive = m_active == id;
        m_documents.erase(found);
        if (m_documents.empty()) m_active = 0;
        else if (wasActive) m_active = m_documents[std::min(index, m_documents.size() - 1)].id;
        return true;
    }
private:
    std::vector<ModelDocument> m_documents;
    uint64_t m_active = 0;
    uint64_t m_next = 1;
};

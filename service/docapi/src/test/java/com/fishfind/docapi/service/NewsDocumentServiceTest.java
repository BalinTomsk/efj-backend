package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.NewsDocumentCache;
import com.fishfind.docapi.repo.NewsQueryCache;
import com.fishfind.docapi.repo.NewsWrite;
import com.fishfind.docapi.repo.NewsWriteRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Every news write -- POST, PUT and import -- goes through this service to the (MySQL)
 * {@link NewsWriteRepository}: validated first, never via the document store, caches cleared after.
 */
class NewsDocumentServiceTest {

    private final NewsDocumentCache store = mock(NewsDocumentCache.class);
    private final NewsQueryCache queryCache = mock(NewsQueryCache.class);
    private final NewsWriteRepository writes = mock(NewsWriteRepository.class);
    private final NewsDocumentService service =
            new NewsDocumentService(store, new ObjectMapper(), writes, queryCache);

    @Test
    void addWritesThroughTheWriteRepositoryAndClearsBothCaches() {
        when(writes.insert(any())).thenReturn("new-id");

        assertThat(service.add("{\"title\":\"Spring opener\",\"author_link\":\"http://a\"}")).isEqualTo("new-id");

        ArgumentCaptor<NewsWrite> w = ArgumentCaptor.forClass(NewsWrite.class);
        verify(writes).insert(w.capture());
        assertThat(w.getValue().title()).isEqualTo("Spring opener");
        assertThat(w.getValue().authorLink()).isEqualTo("http://a");
        verify(queryCache).clear();
        verify(store).clear();
        // The document store is read-only for news: nothing may write through it.
        verify(store, never()).addDocument(any());
        verify(store, never()).updateDocument(any(), any());
    }

    @Test
    void updateReturnsTheIdAndClearsBothCaches() {
        when(writes.update(eq("g1"), any())).thenReturn(true);

        assertThat(service.update(" g1 ", "{\"title\":\"Edited\"}")).isEqualTo("g1");

        verify(writes).update(eq("g1"), any());
        verify(queryCache).clear();
        verify(store).clear();
    }

    /** SQL Server's UPDATE silently matched nothing and still answered 200; this is a real 404 now. */
    @Test
    void updateOfAnUnknownIdIsA404AndLeavesTheCachesAlone() {
        when(writes.update(any(), any())).thenReturn(false);

        assertThatThrownBy(() -> service.update("nope", "{\"title\":\"x\"}"))
                .isInstanceOf(DocumentNotFoundException.class);
        verify(queryCache, never()).clear();
        verify(store, never()).clear();
    }

    @Test
    void importUsesTheInterchangeShape() {
        when(writes.insert(any())).thenReturn("imported-id");

        assertThat(service.importInterchange("{\"title\":\"T\",\"authorLink\":\"http://a\",\"photoAlt2\":\"L2\"}"))
                .isEqualTo("imported-id");

        ArgumentCaptor<NewsWrite> w = ArgumentCaptor.forClass(NewsWrite.class);
        verify(writes).insert(w.capture());
        assertThat(w.getValue().authorLink()).isEqualTo("http://a");
        assertThat(w.getValue().photo2().alt()).isEqualTo("L2");
        verify(queryCache).clear();
    }

    /**
     * Client errors are 400s raised BEFORE the repository -- so they can never count against the
     * shared sqlBreaker, which is what a SQL-side RAISERROR used to do.
     */
    @Test
    void invalidBodiesAre400sThatNeverReachTheDatabase() {
        for (String bad : new String[] {null, "", "  ", "{not json", "[1]", "{\"author\":\"no title\"}"}) {
            assertThatThrownBy(() -> service.add(bad)).as("add(%s)", bad).isInstanceOf(InvalidDocumentException.class);
            assertThatThrownBy(() -> service.importInterchange(bad)).as("import(%s)", bad)
                    .isInstanceOf(InvalidDocumentException.class);
            assertThatThrownBy(() -> service.update("g1", bad)).as("update(%s)", bad)
                    .isInstanceOf(InvalidDocumentException.class);
        }
        assertThatThrownBy(() -> service.update(" ", "{\"title\":\"x\"}")).isInstanceOf(InvalidDocumentException.class);
        verifyNoInteractions(writes);
    }

    /** Under the default profile the beans are uncached; eviction must then be a harmless no-op. */
    @Test
    void worksWithUncachedBeans() {
        DocumentStore plainStore = mock(DocumentStore.class);
        NewsWriteRepository w = mock(NewsWriteRepository.class);
        when(w.insert(any())).thenReturn("id");
        NewsDocumentService plain = new NewsDocumentService(plainStore, new ObjectMapper(), w,
                mock(com.fishfind.docapi.repo.NewsQueryRepository.class));

        assertThat(plain.add("{\"title\":\"T\"}")).isEqualTo("id");
    }
}

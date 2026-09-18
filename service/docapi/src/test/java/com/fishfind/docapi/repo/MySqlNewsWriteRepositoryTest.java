package com.fishfind.docapi.repo;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.sql.Types;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Binding and result handling against a mocked statement. The procedures themselves -- and this
 * class's binding against a real MySQL 8 engine -- are covered by
 * {@code envfish-db/mysql/UNIT_TESTS/unit_test@NewsAdminWrite.sql} tests 11-17 and the 2026-09-18
 * real-engine run recorded in the CHANGELOG.
 */
class MySqlNewsWriteRepositoryTest {

    private final JdbcTemplate mysqlJdbc = mock(JdbcTemplate.class);
    private final MySqlNewsWriteRepository repository = new MySqlNewsWriteRepository(mysqlJdbc);

    private static final byte[] P0 = {1, 2, 3};
    private static final byte[] P2 = {7, 8, 9};

    private static NewsWrite write() {
        return new NewsWrite("Title", "Author", "http://a", "Source", "http://s", "http://v",
                "p0", null, "p2", "CA", Timestamp.valueOf("2026-09-15 00:00:00"),
                "lake-guid", "f1", null, "f3",
                new NewsWrite.Photo(P0, "C0", "L0"),
                null,
                new NewsWrite.Photo(P2, null, "L2"));
    }

    /** Runs the captured callback against a statement whose one result row is {@code column=value}. */
    private PreparedStatement runCallback(String sql, String column, Object value) throws Exception {
        @SuppressWarnings("unchecked")
        ArgumentCaptor<PreparedStatementCallback<Object>> cb = ArgumentCaptor.forClass(PreparedStatementCallback.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(ps.execute()).thenReturn(true);
        when(ps.getResultSet()).thenReturn(rs);
        when(ps.getMoreResults(anyInt())).thenReturn(false);
        when(ps.getUpdateCount()).thenReturn(-1);
        when(rs.next()).thenReturn(true, false);
        if (value instanceof Integer i) {
            when(rs.getInt(column)).thenReturn(i);
        } else {
            when(rs.getString(column)).thenReturn((String) value);
        }
        when(mysqlJdbc.execute(eq(sql), cb.capture())).thenAnswer(inv -> cb.getValue().doInPreparedStatement(ps));
        return ps;
    }

    @Test
    void insertCallsTheMySqlProcedureWithAll24ParametersInOrder() throws Exception {
        PreparedStatement ps = runCallback(MySqlNewsWriteRepository.INSERT_SQL, "news_id", "new-uuid");

        assertThat(repository.insert(write())).isEqualTo("new-uuid");

        verify(ps).setString(1, "Title");
        verify(ps).setString(2, "Author");
        verify(ps).setString(3, "http://a");
        verify(ps).setString(4, "Source");
        verify(ps).setString(5, "http://s");
        verify(ps).setString(6, "http://v");
        verify(ps).setString(7, "p0");
        verify(ps).setNull(8, Types.VARCHAR);                      // paragraph1 absent
        verify(ps).setString(9, "p2");
        verify(ps).setString(10, "CA");
        verify(ps).setTimestamp(11, Timestamp.valueOf("2026-09-15 00:00:00"));
        verify(ps).setString(12, "lake-guid");
        verify(ps).setString(13, "f1");
        verify(ps).setNull(14, Types.VARCHAR);
        verify(ps).setString(15, "f3");
        verify(ps).setBytes(16, P0);                               // slot 0
        verify(ps).setString(17, "C0");
        verify(ps).setString(18, "L0");
        verify(ps).setNull(19, Types.LONGVARBINARY);               // slot 1 empty (NONE)
        verify(ps).setNull(20, Types.VARCHAR);
        verify(ps).setNull(21, Types.VARCHAR);
        verify(ps).setBytes(22, P2);                               // slot 2
        verify(ps).setNull(23, Types.VARCHAR);
        verify(ps).setString(24, "L2");
    }

    @Test
    void aMissingStampIsBoundAsNullSoTheProcedureDefaultsIt() throws Exception {
        PreparedStatement ps = runCallback(MySqlNewsWriteRepository.INSERT_SQL, "news_id", "id");
        NewsWrite w = write();
        repository.insert(new NewsWrite(w.title(), null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, null, null));

        verify(ps).setNull(11, Types.TIMESTAMP);
    }

    @Test
    void updateBindsTheIdFirstThenFieldsThenSlotZeroOnly() throws Exception {
        PreparedStatement ps = runCallback(MySqlNewsWriteRepository.UPDATE_SQL, "found", 1);

        assertThat(repository.update("the-id", write())).isTrue();

        verify(ps).setString(1, "the-id");
        verify(ps).setString(2, "Title");
        verify(ps).setTimestamp(12, Timestamp.valueOf("2026-09-15 00:00:00"));
        verify(ps).setString(16, "f3");
        verify(ps).setBytes(17, P0);
        verify(ps).setString(18, "C0");
        verify(ps).setString(19, "L0");
    }

    @Test
    void updateOfAnUnknownIdReportsFalse() throws Exception {
        runCallback(MySqlNewsWriteRepository.UPDATE_SQL, "found", 0);

        assertThat(repository.update("nope", write())).isFalse();
    }

    @Test
    void theProcedureCallsHaveOnePlaceholderPerParameter() {
        assertThat(MySqlNewsWriteRepository.INSERT_SQL).startsWith("CALL sp_news_doc_insert(");
        assertThat(MySqlNewsWriteRepository.INSERT_SQL.chars().filter(c -> c == '?').count()).isEqualTo(24);
        assertThat(MySqlNewsWriteRepository.UPDATE_SQL).startsWith("CALL sp_news_doc_update(");
        assertThat(MySqlNewsWriteRepository.UPDATE_SQL.chars().filter(c -> c == '?').count()).isEqualTo(19);
    }

    @Test
    void neverUsesAnythingButTheTemplateItWasGiven() {
        when(mysqlJdbc.execute(any(String.class), any(PreparedStatementCallback.class))).thenReturn("x");
        repository.insert(write());
        verify(mysqlJdbc).execute(eq(MySqlNewsWriteRepository.INSERT_SQL), any(PreparedStatementCallback.class));
    }
}

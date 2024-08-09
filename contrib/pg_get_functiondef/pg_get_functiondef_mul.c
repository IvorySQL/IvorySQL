#include "postgres.h"
#include "fmgr.h"
#include "utils/elog.h"
#include "lib/stringinfo.h"
#include "executor/spi.h"
#include "utils/array.h"
#include "catalog/pg_type_d.h"
#include "funcapi.h"

typedef struct FunctionInfo_fctx *FunctionInfo_fctx;
struct FunctionInfo_fctx
{
    TupleDesc result_desc;
    AttInMetadata *result_tuple_meta;
    Oid *oids;
    int cursor;
    int count;
    SPITupleTable *spi_table;
};

PG_FUNCTION_INFO_V1(pg_get_functiondef_mul);

Datum pg_get_functiondef_mul(PG_FUNCTION_ARGS)
{
    FuncCallContext *funcctx;
    FunctionInfo_fctx info = NULL;
    if (SRF_IS_FIRSTCALL())
    {
        StringInfoData query;
        AnyArrayType *oids_array = PG_GETARG_ANY_ARRAY_P(1);
        Datum *oids;
        int count;
        TupleDesc tuple_desc;

        if (SPI_OK_CONNECT != SPI_connect())
        {
            ereport(ERROR, errmsg("SPI connect failed!"));
            PG_RETURN_NULL();
        }

        funcctx = SRF_FIRSTCALL_INIT();
        info = (struct FunctionInfo_fctx *)palloc(sizeof(struct FunctionInfo_fctx));
        funcctx->user_fctx = info;

        if (get_call_result_type(fcinfo, NULL, &tuple_desc) != TYPEFUNC_COMPOSITE)
        {
            ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("function returning record called in context that cannot accept type record")));
        }
        info->result_tuple_meta = TupleDescGetAttInMetadata(tuple_desc);
        info->result_desc = tuple_desc;

        deconstruct_array_builtin((ArrayType *)oids_array, OIDOID, &oids, NULL, &count);
        info->oids = palloc((count + 1) * sizeof(Oid));
        info->oids[0] = PG_GETARG_OID(0);
        for (int i = 1; i <= count; i++)
        {
            info->oids[i] = DatumGetObjectId(oids[i - 1]);
        }
        info->count = count + 1;
        initStringInfo(&query);
        appendStringInfo(&query, "SELECT ");
        appendStringInfo(&query, "pg_get_functiondef(%d)", info->oids[0]);
        for (int i = 1; i < count; i++)
        {
            appendStringInfo(&query, ", pg_get_functiondef(%d)", info->oids[i]);
        }
        appendStringInfo(&query, ", pg_get_functiondef(%d);", info->oids[info->count - 1]);
        if (SPI_execute(query.data, true, 0) != SPI_OK_SELECT)
        {
            ereport(ERROR, errmsg("SPI select failed!"));
            SPI_finish();
            PG_RETURN_NULL();
        }
        info->spi_table = SPI_tuptable;
        info->cursor = 1;
    }
    funcctx = SRF_PERCALL_SETUP();
    info = (FunctionInfo_fctx)(funcctx->user_fctx);
    if (info->cursor > info->count)
    {
        pfree(info->oids);
        FreeTupleDesc(info->result_desc);
        pfree(info);
        SPI_finish();
        SRF_RETURN_DONE(funcctx);
    }
    else
    {
        char **tuple_values;
        HeapTuple tuple;
        Datum tuple_return;
        char *record = SPI_getvalue(info->spi_table->vals[0], info->spi_table->tupdesc, info->cursor);
        tuple_values = palloc(2 * sizeof(char *));
        tuple_values[0] = palloc(sizeof(char) * 16);
        sprintf(tuple_values[0], "%d", info->oids[info->cursor - 1]);
        if (record)
        {
            tuple_values[1] = palloc(sizeof(char) * (strlen(record) + 1));
            sprintf(tuple_values[1], "%s", record);
        }
        else
        {
            tuple_values[1] = palloc(sizeof(char) * 1);
            memset(tuple_values[1], 0, sizeof(char));
        }
        tuple = BuildTupleFromCStrings(info->result_tuple_meta, tuple_values);
        info->cursor += 1;
        tuple_return = HeapTupleGetDatum(tuple);
        pfree(tuple_values[0]);
        pfree(tuple_values[1]);
        pfree(tuple_values);
        SRF_RETURN_NEXT(funcctx, tuple_return);
    }
}